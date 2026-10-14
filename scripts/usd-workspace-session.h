// Session members; included in Session after snapshot().
  std::set<std::string> workspaceSourceFiles() {
    // Owned stages use anonymous copies, so refresh only the original graph's
    // dependency cache before inspecting changed graph membership on disk.
    if(!workingLayers.empty())for(const auto &copy:workingLayers){auto cached=SdfLayer::Find(copy.original);if(cached)cached->Reload(true);}
    std::vector<SdfLayerRefPtr> layers;std::vector<std::string> assets,missing;
    if(!UsdUtilsComputeAllDependencies(SdfAssetPath(source),&layers,&assets,&missing) || !missing.empty())
      throw std::runtime_error("Workspace source has missing external dependencies");
    std::set<std::string> files;
    auto add=[&](std::string path){while(ArIsPackageRelativePath(path))path=ArSplitPackageRelativePathOuter(path).first;files.insert(fs::canonical(path).string());};
    add(source);for(auto l:layers)if(!l->IsAnonymous())add(l->GetRealPath());for(auto a:assets)add(a);
    if(files.size()>4096)throw std::runtime_error("Workspace exceeds 4096 external dependencies");return files;
  }
  JsArray dependencyRecords(const fs::path &root) {
    JsArray records;uintmax_t total=0;
    for(auto path:workspaceSourceFiles()) {
      total+=fs::file_size(path);if(total>workspace::bundleLimit)throw std::runtime_error("Workspace dependencies exceed 256 MiB");
      records.emplace_back(workspace::file(root,path,workspace::fileLimit));
    }
    return records;
  }
  void checkDependencies(const fs::path &root,const JsArray &records) {
    std::set<std::string> unique;uintmax_t total=0;
    for(const auto &v:records) {
      auto r=workspace::object(v);auto relative=string(field(r,"path"));
      if(relative.empty() || fs::path(relative).is_absolute() || relative.size()>4096)throw std::runtime_error("External source paths must be relative filesystem paths");
      auto path=fs::canonical(root/relative);if(!unique.insert(path.string()).second)throw std::runtime_error("Duplicate workspace source dependency");
      total+=fs::file_size(path);if(total>workspace::bundleLimit)throw std::runtime_error("Workspace dependencies exceed 256 MiB");
      workspace::checked(path,r,workspace::fileLimit);
    }
  }
  JsValue saveWorkspace(const Object &o) {
    if(!sourceConflicts().empty())throw std::runtime_error("Source conflict: resolve_sources explicitly before saving workspace");
    auto root=fs::absolute(string(field(o,"destination"))).lexically_normal();
    if(!fs::exists(root)) {if(!fs::is_directory(root.parent_path()))throw std::runtime_error("Workspace parent directory does not exist");fs::create_directory(root);workspace::sync(root.parent_path(),true);}
    if(!fs::is_directory(root) || fs::is_symlink(fs::symlink_status(root)))throw std::runtime_error("Workspace must be a real directory");
    root=fs::canonical(root);workspace::Lock lock(root);
    auto manifestPath=root/"workspace.json";
    if(fs::is_symlink(fs::symlink_status(manifestPath)))throw std::runtime_error("Workspace manifest must not be a symlink");
    if(fs::exists(manifestPath)) {
      auto current=workspace::manifest(manifestPath);
      if(workspacePath!=root.string() || string(field(current,"generation"))!=workspaceGeneration)
        throw std::runtime_error("Workspace changed or belongs to another session; reopen before saving");
    } else if(workspacePath==root.string())throw std::runtime_error("Workspace manifest disappeared; reopen or save to a new directory");
    if(workspace::digest(workspace::read(source,workspace::fileLimit))!=openedSourceHash)
      throw std::runtime_error("Original source changed; reload and resolve edits before workspace save");
    if(!workspaceDependencies.empty())checkDependencies(workspacePath,workspaceDependencies);
    auto dependencies=dependencyRecords(root);auto state=capture();auto fingerprint=stateHash();
    std::string gen="g-"+newIdentity().substr(6);auto generations=root/"generations",directory=generations/gen;
    if(fs::is_symlink(fs::symlink_status(generations)))throw std::runtime_error("Workspace generations must not be a symlink");
    fs::create_directory(generations);workspace::sync(root,true);fs::create_directory(directory);
    auto temporary=root/(".manifest-"+gen+".tmp");bool published=false;
    try {
      workspace::fault("generation_created");
      JsArray layers,rules,working;
      auto session=SdfLayer::CreateAnonymous();session->TransferContent(stage->GetSessionLayer());session->SetSubLayerPaths({});
      std::string sessionText;session->ExportToString(&sessionText);
      workspace::write(directory/"session.usda",sessionText);
      auto sessionRecord=workspace::file(root,directory/"session.usda",workspace::layerLimit);
      for(size_t i=0;i<state.layers.size();++i) {
        auto path=directory/("layer-"+std::to_string(i)+".usda");workspace::write(path,state.layers[i].second);
        auto record=workspace::file(root,path,workspace::layerLimit);record["name"]=JsValue(state.layers[i].first);layers.emplace_back(record);
      }
      for(const auto &r:state.rules.GetRules())rules.emplace_back(Object{{"path",JsValue(r.first.GetString())},{"rule",JsValue(int(r.second))}});
      if(!workingLayers.empty())working=exportWorking(directory,root);
      workspace::sync(directory,true);workspace::sync(generations,true);workspace::fault("layers_synced");
      auto sourceRecord=workspace::file(root,source,workspace::fileLimit);
      if(string(field(sourceRecord,"sha256"))!=openedSourceHash)throw std::runtime_error("Original source changed during workspace save");
      Object manifest{{"format",JsValue("atlas-usd-workspace")},{"version",JsValue(workingLayers.empty()?1:2)},{"generation",JsValue(gen)},
        {"source",JsValue(sourceRecord)},{"dependencies",JsValue(dependencies)},{"session",JsValue(sessionRecord)},
        {"layers",JsValue(layers)},{"edit_target",JsValue(targetName)},{"load_rules",JsValue(rules)},
        {"prim_limit",JsValue(int(primLimit))},{"history_policy",JsValue("empty-on-open")}};
      if(!workingLayers.empty()){manifest["working_sources"]=JsValue(working);manifest["edit_context"]=JsValue(targetContext);manifest["edit_node"]=JsValue(targetNode);}
      auto text=workspace::json(JsValue(manifest));if(text.size()>workspace::manifestLimit)throw std::runtime_error("Workspace manifest exceeds 1 MiB");
      workspace::write(temporary,text);
      // Validate files and source fingerprints again before making this generation visible.
      checkDependencies(root,dependencies);workspace::checked(directory/"session.usda",sessionRecord,workspace::layerLimit);
      for(const auto &v:layers){auto r=workspace::object(v);workspace::checked(root/string(field(r,"path")),r,workspace::layerLimit);}
      // Recompose the serialized layer stack with the saved payload rules before
      // publication, rather than relying only on successful individual exports.
      auto verifySession=SdfLayer::CreateAnonymous();
      if(!verifySession->ImportFromString(sessionText))throw std::runtime_error("Cannot validate workspace session export");
      std::vector<SdfLayerRefPtr> verifyLayers;std::vector<std::string> verifyPaths;
      for(const auto &entry:state.layers){auto layer=SdfLayer::CreateAnonymous();if(!layer->ImportFromString(entry.second))throw std::runtime_error("Cannot validate workspace layer export");verifyLayers.push_back(layer);verifyPaths.push_back(layer->GetIdentifier());}
      verifySession->SetSubLayerPaths(verifyPaths);auto verifyStage=UsdStage::Open(stage->GetRootLayer(),verifySession,UsdStage::LoadNone);
      if(!verifyStage)throw std::runtime_error("Cannot validate saved workspace composition");
      verifyStage->SetLoadRules(state.rules);if(!verifyStage->GetCompositionErrors().empty())throw std::runtime_error("Saved workspace has composition errors");
      size_t prims=0;for(auto p:verifyStage->TraverseAll())if(++prims>primLimit)throw std::runtime_error("Saved workspace exceeds prim limit");
      workspace::fault("manifest_synced");
      fs::rename(temporary,manifestPath);published=true;
      workspace::sync(root,true);workspace::fault("manifest_published");
      workspacePath=root.string();workspaceGeneration=gen;savedState=fingerprint;workspaceDependencies=dependencies;
      return JsValue(Object{{"destination",JsValue(workspacePath)},{"kind",JsValue("workspace")},{"generation",JsValue(gen)},{"revision",JsValue(revision)}});
    } catch(...) {
      // Never remove published or historical data. Interrupted generations are ignored.
      if(!published){fs::remove(temporary);fs::remove_all(directory);}throw;
    }
  }
  JsValue openWorkspace(const Object &o) {
    auto root=fs::canonical(string(field(o,"source")));auto manifestPath=root/"workspace.json";
    if(fs::is_symlink(fs::symlink_status(manifestPath)))throw std::runtime_error("Workspace manifest must not be a symlink");
    auto m=workspace::manifest(manifestPath);auto gen=string(field(m,"generation"));
    if(!workspace::generation(gen))throw std::runtime_error("Invalid workspace generation identity");
    if(string(field(m,"history_policy"))!="empty-on-open")throw std::runtime_error("Unsupported workspace history policy");
    double limit=number(field(m,"prim_limit"));if(limit<1 || limit>100000 || std::floor(limit)!=limit)throw std::runtime_error("Invalid workspace prim limit");
    auto dependencies=workspace::array(field(m,"dependencies"),4096);if(dependencies.empty())throw std::runtime_error("Workspace has no source dependency records");
    checkDependencies(root,dependencies);
    auto sourceRecord=workspace::object(field(m,"source"));auto relative=string(field(sourceRecord,"path"));
    if(fs::path(relative).is_absolute() || relative.empty() || relative.size()>4096)throw std::runtime_error("Workspace source must be a relative filesystem path");
    auto file=fs::canonical(root/relative).string();workspace::checked(file,sourceRecord,workspace::fileLimit);
    bool found=false;for(const auto &v:dependencies)if(fs::canonical(root/string(field(workspace::object(v),"path"))).string()==file)found=true;
    if(!found)throw std::runtime_error("Source identity is missing from workspace dependencies");
    auto readLayer=[&](const Object &r) {
      auto path=workspace::owned(root,string(field(r,"path")),gen);auto text=workspace::checked(path,r,workspace::layerLimit);
      auto layer=SdfLayer::CreateAnonymous(path.filename().string());
      if(!layer->ImportFromString(text) || !layer->GetSubLayerPaths().empty() || !layer->GetCompositionAssetDependencies().empty())
        throw std::runtime_error("Invalid owned layer; new source dependencies and nested layer stacks are not supported");
      return layer;
    };
    TfErrorMark errors;auto session=readLayer(workspace::object(field(m,"session")));
    std::vector<AuthorLayer> layers;std::vector<std::string> paths;std::set<std::string> names,ownedPaths;
    ownedPaths.insert(string(field(workspace::object(field(m,"session")),"path")));size_t bytes=0;
    for(const auto &v:workspace::array(field(m,"layers"),8)) {
      auto r=workspace::object(v);auto name=string(field(r,"name"));
      if(!workspace::name(name) || !names.insert(name).second || !ownedPaths.insert(string(field(r,"path"))).second)throw std::runtime_error("Invalid or duplicate owned layer name/path");
      bytes+=size_t(number(field(r,"bytes")));if(bytes>workspace::layerLimit)throw std::runtime_error("Owned layer stack exceeds 32 MiB");
      auto layer=readLayer(r);layers.push_back({name,layer});paths.push_back(layer->GetIdentifier());
    }
    auto selected=string(field(m,"edit_target"));std::vector<WorkingLayer> working;std::vector<fs::path> ownedFiles;
    auto stageRoot=SdfLayer::FindOrOpen(file);std::string context;int node=-1;
    if(number(field(m,"version"))==2) {
      auto records=workspace::array(field(m,"working_sources"),64);if(records.empty())throw std::runtime_error("Version 2 requires a source working graph");
      std::set<std::string> allowed;for(const auto &v:dependencies)allowed.insert(fs::canonical(root/string(field(workspace::object(v),"path"))).string());
      std::set<std::string> originals;
      for(const auto &v:records){auto r=workspace::object(v);auto original=workspace::object(field(r,"original"));auto relative=string(field(original,"path"));
        if(relative.empty() || fs::path(relative).is_absolute() || relative.size()>4096)throw std::runtime_error("Working original requires a relative source path");
        auto originalPath=fs::canonical(root/relative).string();if(!allowed.count(originalPath))throw std::runtime_error("Working original is not a recorded dependency");
        workspace::checked(originalPath,original,workspace::fileLimit);
        if(!originals.insert(originalPath).second || !ownedPaths.insert(string(field(r,"path"))).second)throw std::runtime_error("Duplicate working source identity/path");
        auto path=workspace::owned(root,string(field(r,"path")),gen);auto text=workspace::checked(path,r,workspace::layerLimit);bytes+=text.size();
        if(bytes>workspace::layerLimit)throw std::runtime_error("Owned source graph exceeds 32 MiB");auto layer=SdfLayer::CreateAnonymous(path.filename().string());
        if(!layer->ImportFromString(text))throw std::runtime_error("Invalid source working copy");
        working.push_back({originalPath,string(field(original,"sha256")),layer});ownedFiles.push_back(path);
      }
      if(working[0].original!=file)throw std::runtime_error("Working root does not match source identity");
      for(size_t i=0;i<working.size();++i)workspace::repath(working[i].layer,[&](const std::string &path){
        if(path.empty())return path;if(fs::path(path).is_absolute())throw std::runtime_error("Owned source assets must be portable relative paths");
        auto resolved=fs::canonical(ownedFiles[i].parent_path()/path).string();
        for(size_t j=0;j<ownedFiles.size();++j)if(resolved==ownedFiles[j].string())return working[j].layer->GetIdentifier();
        if(!allowed.count(resolved))throw std::runtime_error("Unrecorded source asset in owned graph");return resolved;
      });
      stageRoot=working[0].layer;context=string(field(m,"edit_context"));double n=number(field(m,"edit_node"));
      if(n< -1 || n>1024 || std::floor(n)!=n)throw std::runtime_error("Invalid stored edit mapping");node=int(n);
    }
    if(selected!="session" && !names.count(selected) && selected.rfind("working:",0)!=0)throw std::runtime_error("Workspace selected target is missing");
    session->SetSubLayerPaths(paths);auto candidate=UsdStage::Open(stageRoot,session,UsdStage::LoadNone);
    if(!candidate)throw std::runtime_error("Cannot compose workspace source");
    UsdStageLoadRules rules;std::set<SdfPath> rulePaths;
    for(const auto &v:workspace::array(field(m,"load_rules"),4096)) {
      auto r=workspace::object(v);SdfPath path(string(field(r,"path")));double rule=number(field(r,"rule"));
      if(!path.IsAbsolutePath() || (!path.IsPrimPath() && path!=SdfPath::AbsoluteRootPath()) || !rulePaths.insert(path).second || rule<0 || rule>2 || std::floor(rule)!=rule)
        throw std::runtime_error("Invalid or duplicate payload load rule");
      rules.AddRule(path,UsdStageLoadRules::Rule(int(rule)));
    }
    candidate->SetLoadRules(rules);if(!errors.IsClean() || !candidate->GetCompositionErrors().empty())throw std::runtime_error("Cannot compose workspace layers/payloads");
    auto oldStage=stage;auto oldSource=source;auto oldLimit=primLimit;auto oldRevision=revision;auto oldLayers=authorLayers;auto oldTarget=targetName;
    auto oldWorkspace=workspacePath,oldGeneration=workspaceGeneration,oldSaved=savedState,oldHash=openedSourceHash;auto oldDependencies=workspaceDependencies;
    auto oldWorking=workingLayers;auto oldWorkingDeps=workingDependencies;auto oldContext=targetContext;auto oldNode=targetNode;
    stage=candidate;source=file;primLimit=size_t(limit);authorLayers=layers;workingLayers=working;workingDependencies.clear();workspacePath=root.string();workspaceGeneration=gen;
    workspaceDependencies=dependencies;openedSourceHash=string(field(sourceRecord,"sha256"));++revision;
    try {
      if(!workingLayers.empty()){workingDependencies=dependencyRecords(fs::path(source).parent_path());}
      if(selected.rfind("working:",0)==0)selectWorking(selected,context,node);else select(selected);
      valid();capture();
      // Require complete dependency identities, including unloaded payloads and textures.
      std::set<std::string> recorded;for(const auto &v:dependencies)recorded.insert(fs::canonical(root/string(field(workspace::object(v),"path"))).string());
      if(recorded!=workspaceSourceFiles())throw std::runtime_error("Workspace source dependency membership changed");
      savedState=stateHash();auto result=snapshot(0).GetJsObject();undoHistory.clear();redoHistory.clear();
      result["undo_count"]=JsValue(0);result["redo_count"]=JsValue(0);return JsValue(result);
    } catch(...) {
      stage=oldStage;source=oldSource;primLimit=oldLimit;revision=oldRevision;authorLayers=oldLayers;targetName=oldTarget;
      workspacePath=oldWorkspace;workspaceGeneration=oldGeneration;savedState=oldSaved;openedSourceHash=oldHash;workspaceDependencies=oldDependencies;
      workingLayers=oldWorking;workingDependencies=oldWorkingDeps;targetContext=oldContext;targetNode=oldNode;throw;
    }
  }
