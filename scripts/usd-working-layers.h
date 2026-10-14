// Session members implementing explicitly owned copies of a source layer graph.
  double targetTime(double stageTime) {
    return stage->GetEditTarget().GetMapFunction().GetTimeOffset().GetInverse()*stageTime;
  }
  JsArray sourceConflicts() {
    JsArray conflicts;
    for(const auto &v:workingDependencies) {
      auto record=workspace::object(v);auto path=fs::path(source).parent_path()/string(field(record,"path"));
      try {workspace::checked(path,record,workspace::fileLimit);}
      catch(const std::exception &e){conflicts.emplace_back(Object{{"source",JsValue(path.lexically_normal().string())},{"reason",JsValue(e.what())}});}
    }
    return conflicts;
  }
  JsValue workingSnapshot() {
    JsArray rows;for(size_t i=0;i<workingLayers.size();++i)rows.emplace_back(Object{{"name",JsValue("working:"+std::to_string(i))},
      {"source",JsValue(workingLayers[i].original)},{"identifier",JsValue(workingLayers[i].layer->GetIdentifier())},{"selected",JsValue(target()==workingLayers[i].layer)}});
    return JsValue(rows);
  }
  std::vector<UsdEditTarget> mappedTargets(size_t index,const std::string &context) {
    if(index>=workingLayers.size())throw std::runtime_error("Unknown source working copy");
    auto layer=workingLayers[index].layer;std::vector<UsdEditTarget> targets;
    if(context.empty()) {
      auto stack=stage->GetLayerStack(false);
      if(std::find(stack.begin(),stack.end(),layer)==stack.end())throw std::runtime_error("Referenced layer requires a concrete prim edit context");
      targets.push_back(stage->GetEditTargetForLocalLayer(layer));return targets;
    }
    SdfPath path(context);auto prim=stage->GetPrimAtPath(path);
    if(!path.IsAbsolutePath() || !path.IsPrimPath() || !prim || prim.IsInstanceProxy())throw std::runtime_error("Source edit context requires a loaded concrete prim; proxies are read-only");
    for(const auto &node:prim.GetPrimIndex().GetNodeRange()) {
      auto layers=node.GetLayerStack()->GetLayers();
      if(std::find(layers.begin(),layers.end(),layer)!=layers.end()) {
        UsdEditTarget candidate(layer,node);
        if(!candidate.MapToSpecPath(path).IsEmpty() && std::find(targets.begin(),targets.end(),candidate)==targets.end())targets.push_back(candidate);
        if(targets.size()>1024)throw std::runtime_error("Source context exceeds 1024 edit mappings");
      }
    }
    if(targets.empty())throw std::runtime_error("Source layer does not contribute to the selected context");return targets;
  }
  size_t workingIndex(const std::string &name) {
    for(size_t i=0;i<workingLayers.size();++i)if(name=="working:"+std::to_string(i) || name==workingLayers[i].original)return i;
    throw std::runtime_error("Unknown source working copy");
  }
  void selectWorking(const std::string &name,const std::string &context,int node) {
    auto index=workingIndex(name);auto targets=mappedTargets(index,context);
    if(node<0){if(targets.size()!=1)throw std::runtime_error("Ambiguous source/variant mapping; inspect source_targets and select a node");node=0;}
    if(size_t(node)>=targets.size())throw std::runtime_error("Invalid source edit mapping index");
    stage->SetEditTarget(targets[node]);targetName="working:"+std::to_string(index);targetContext=context;targetNode=node;
  }
  JsValue sourceTargets(const Object &o) {
    JsArray rows;auto context=o.count("path")?string(field(o,"path")):"";
    for(size_t i=0;i<workingLayers.size();++i) {
      std::vector<UsdEditTarget> targets;
      try{targets=mappedTargets(i,context);}catch(const std::exception &){continue;}
      for(size_t j=0;j<targets.size();++j){auto offset=targets[j].GetMapFunction().GetTimeOffset();
        rows.emplace_back(Object{{"name",JsValue("working:"+std::to_string(i))},{"source",JsValue(workingLayers[i].original)},
          {"node",JsValue(int(j))},{"context",JsValue(context)},{"spec_path",JsValue(context.empty()?"/":targets[j].MapToSpecPath(SdfPath(context)).GetString())},
          {"time_offset",JsValue(offset.GetOffset())},{"time_scale",JsValue(offset.GetScale())}});}
    }
    return JsValue(Object{{"targets",JsValue(rows)}});
  }
  void beginWorking() {
    if(!workingLayers.empty())throw std::runtime_error("Source working copies already exist");
    if(workspace::digest(workspace::read(source,workspace::fileLimit))!=openedSourceHash)throw std::runtime_error("Source changed since open; explicitly reopen before making working copies");
    std::vector<SdfLayerRefPtr> originals;std::vector<std::string> assets,missing;
    if(!UsdUtilsComputeAllDependencies(SdfAssetPath(source),&originals,&assets,&missing) || !missing.empty())throw std::runtime_error("Source graph has missing dependencies");
    if(originals.size()>64)throw std::runtime_error("Working source graph exceeds 64 layers");
    std::set<std::string> paths;for(auto layer:originals){auto path=layer->GetRealPath();if(path.empty() || ArIsPackageRelativePath(path))throw std::runtime_error("Package-relative/custom-resolver source editing is unsupported; unpack to filesystem USD layers");paths.insert(fs::canonical(path).string());}
    std::vector<std::string> ordered{source};paths.erase(source);ordered.insert(ordered.end(),paths.begin(),paths.end());
    auto dependencies=dependencyRecords(fs::path(source).parent_path());std::vector<WorkingLayer> copies;
    size_t bytes=0;
    for(const auto &path:ordered){auto content=workspace::read(path,workspace::fileLimit);auto clone=SdfLayer::OpenAsAnonymous(path);
      if(!clone)throw std::runtime_error("Cannot read source layer for owned editing");std::string text;clone->ExportToString(&text);bytes+=text.size();
      if(bytes>workspace::layerLimit)throw std::runtime_error("Working source graph exceeds 32 MiB");copies.push_back({path,workspace::digest(content),clone});}
    for(auto &copy:copies)workspace::repath(copy.layer,[&](const std::string &path){
      if(path.empty())return path;auto resolved=fs::weakly_canonical(fs::path(copy.original).parent_path()/path).string();
      for(const auto &candidate:copies)if(candidate.original==resolved)return candidate.layer->GetIdentifier();
      if(!fs::is_regular_file(resolved))throw std::runtime_error("Unsupported or missing external source asset: "+path);return resolved;
    });
    checkDependencies(fs::path(source).parent_path(),dependencies);
    auto candidate=UsdStage::Open(copies[0].layer,stage->GetSessionLayer(),UsdStage::LoadNone);
    if(!candidate || !candidate->GetCompositionErrors().empty())throw std::runtime_error("Cannot compose owned source graph");candidate->SetLoadRules(stage->GetLoadRules());
    workingLayers=std::move(copies);workingDependencies=dependencies;stage=candidate;selectWorking("working:0","",-1);
  }
  void resolveSources(const std::string &action) {
    if(workingLayers.empty() || (action!="reload" && action!="keep_working"))throw std::runtime_error("Source resolution requires working copies and action reload or keep_working");
    auto current=dependencyRecords(fs::path(source).parent_path());
    std::set<std::string> oldPaths,newPaths;for(const auto &v:workingDependencies)oldPaths.insert(string(field(workspace::object(v),"path")));for(const auto &v:current)newPaths.insert(string(field(workspace::object(v),"path")));
    if(oldPaths!=newPaths)throw std::runtime_error("Source dependency graph changed; reimport required before resolving");
    if(action=="reload") {
      for(auto &copy:workingLayers){auto fresh=SdfLayer::OpenAsAnonymous(copy.original);if(!fresh)throw std::runtime_error("Cannot reload owned source copy");
        workspace::repath(fresh,[&](const std::string &path){if(path.empty())return path;auto resolved=fs::weakly_canonical(fs::path(copy.original).parent_path()/path).string();
          for(const auto &candidate:workingLayers)if(candidate.original==resolved)return candidate.layer->GetIdentifier();return resolved;});copy.layer->TransferContent(fresh);}
    }
    for(auto &copy:workingLayers)copy.sha256=workspace::digest(workspace::read(copy.original,workspace::fileLimit));
    workingDependencies=current;openedSourceHash=workspace::digest(workspace::read(source,workspace::fileLimit));
    if(!workspacePath.empty())workspaceDependencies=dependencyRecords(workspacePath);
  }
  JsArray exportWorking(const fs::path &directory,const fs::path &root) {
    JsArray rows;for(size_t i=0;i<workingLayers.size();++i){const auto &copy=workingLayers[i];auto layer=SdfLayer::CreateAnonymous();layer->TransferContent(copy.layer);
      workspace::repath(layer,[&](const std::string &path){if(path.empty())return path;
        for(size_t j=0;j<workingLayers.size();++j)if(path==workingLayers[j].layer->GetIdentifier())return "source-"+std::to_string(j)+".usda";
        if(!fs::path(path).is_absolute() || !fs::is_regular_file(path))throw std::runtime_error("Unresolved owned source asset");return fs::relative(path,directory).generic_string();});
      std::string text;layer->ExportToString(&text);auto path=directory/("source-"+std::to_string(i)+".usda");workspace::write(path,text);
      auto record=workspace::file(root,path,workspace::layerLimit);record["original"]=JsValue(workspace::file(root,copy.original,workspace::fileLimit));rows.emplace_back(record);
    }
    workspace::sync(directory,true);return rows;
  }
