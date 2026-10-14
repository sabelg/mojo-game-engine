// Per-occurrence identity opinions belong to the session, even while a mapped
// source target is selected. The catalog reserves IDs hidden by unloaded payloads.
  VtDictionary identityCatalog() {
    auto data=stage->GetSessionLayer()->GetCustomLayerData();auto found=data.find("atlas_identity_catalog");
    if(found==data.end())return {};
    if(!found->second.IsHolding<VtDictionary>())throw std::runtime_error("Invalid persistent identity catalog");
    auto catalog=found->second.UncheckedGet<VtDictionary>();std::set<std::string> ids;
    if(catalog.size()>primLimit)throw std::runtime_error("Identity catalog exceeds prim budget");
    for(const auto &entry:catalog){SdfPath path(entry.first);
      if(!path.IsAbsolutePath() || !path.IsPrimPath() || !entry.second.IsHolding<std::string>() ||
         !validIdentity(entry.second.UncheckedGet<std::string>()) || !ids.insert(entry.second.UncheckedGet<std::string>()).second)
        throw std::runtime_error("Invalid or duplicate persistent identity catalog entry");}
    return catalog;
  }
  void reconcileIdentities() {
    auto catalog=identityCatalog();std::map<std::string,std::string> owners;
    for(const auto &entry:catalog)owners[entry.second.UncheckedGet<std::string>()]=entry.first;
    std::vector<UsdPrim> ordered;
    for(auto p:stage->TraverseAll())if(p.IsLoaded() && p.IsDefined() && !p.IsAbstract())ordered.push_back(p);
    std::sort(ordered.begin(),ordered.end(),[](const UsdPrim &a,const UsdPrim &b){return a.GetPath()<b.GetPath();});
    auto previous=stage->GetEditTarget();stage->SetEditTarget(stage->GetSessionLayer());
    try {
      std::set<std::string> seen;
      for(auto p:ordered){auto path=p.GetPath().GetString();auto value=p.GetCustomDataByKey(TfToken("atlas:uuid"));
        auto known=catalog.find(path);std::string id=known!=catalog.end()?known->second.UncheckedGet<std::string>():value.IsHolding<std::string>()?value.UncheckedGet<std::string>():"";
        if(!validIdentity(id) || seen.count(id) || (owners.count(id) && owners[id]!=path)) {
          do{id=newIdentity();}while(owners.count(id) || seen.count(id));
        }
        seen.insert(id);owners[id]=path;catalog[path]=VtValue(id);
        if(value!=VtValue(id))p.SetCustomDataByKey(TfToken("atlas:uuid"),VtValue(id));
      }
      if(catalog.size()>primLimit)throw std::runtime_error("Identity catalog exceeds prim budget");
      auto data=stage->GetSessionLayer()->GetCustomLayerData();data["atlas_identity_catalog"]=VtValue(catalog);stage->GetSessionLayer()->SetCustomLayerData(data);
    }catch(...){stage->SetEditTarget(previous);throw;}
    stage->SetEditTarget(previous);
  }
  JsValue identityRows() {
    JsArray rows;auto catalog=identityCatalog();std::set<std::string> loaded;
    size_t count=0;
    for(auto p:UsdPrimRange::Stage(stage,UsdTraverseInstanceProxies(UsdPrimAllPrimsPredicate))) {
      if(++count>primLimit)throw std::runtime_error("Identity traversal exceeds prim budget");
      if(!p.IsLoaded() || !p.IsDefined() || p.IsAbstract())continue;
      auto path=p.GetPath().GetString();loaded.insert(path);auto value=p.GetCustomDataByKey(TfToken("atlas:uuid"));
      std::string id=value.IsHolding<std::string>()?value.UncheckedGet<std::string>():"";
      Object row{{"path",JsValue(path)},{"loaded",JsValue(true)},{"writable",JsValue(!p.IsInstanceProxy())}};
      if(p.IsInstanceProxy()) {
        auto instance=p.GetParent();while(instance.IsInstanceProxy())instance=instance.GetParent();
        auto rootId=instance.GetCustomDataByKey(TfToken("atlas:uuid"));
        if(rootId.IsHolding<std::string>() && validIdentity(rootId.UncheckedGet<std::string>()))
          id="atlas:proxy:"+workspace::digest(rootId.UncheckedGet<std::string>()+"\n"+p.GetPath().MakeRelativePath(instance.GetPath()).GetString()).substr(0,32);
        else id.clear();
        row["instance_root"]=JsValue(instance.GetPath().GetString());row["identity_kind"]=JsValue("derived_proxy");
      }else row["identity_kind"]=JsValue("authored");
      if(validIdentity(id))row["stable_id"]=JsValue(id);rows.emplace_back(row);
    }
    for(const auto &entry:catalog)if(!loaded.count(entry.first))rows.emplace_back(Object{{"path",JsValue(entry.first)},
      {"stable_id",JsValue(entry.second.UncheckedGet<std::string>())},{"loaded",JsValue(false)},{"writable",JsValue(false)},{"identity_kind",JsValue("reserved")}});
    return JsValue(Object{{"identities",JsValue(rows)}});
  }
