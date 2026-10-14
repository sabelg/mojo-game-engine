// Session members: typed channel inspection and atomic tuple-key edits.
  VtValue ownNumericSample(const UsdAttribute &a,double time) {
    auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());VtValue left,right;
    double low,high;
    if(target()->GetBracketingTimeSamplesForPath(path,targetTime(time),&low,&high)) {
      if(!target()->QueryTimeSample(path,low,&left) || !target()->QueryTimeSample(path,high,&right))throw std::runtime_error("Cannot read selected layer keys");
      if(low==high || stage->GetInterpolationType()==UsdInterpolationTypeHeld)return left;
      double weight=std::clamp((targetTime(time)-low)/(high-low),0.0,1.0);
      if(left.IsHolding<VtQuatfArray>()){auto result=left.Get<VtQuatfArray>();const auto &end=right.Get<VtQuatfArray>();
        if(result.size()!=end.size())throw std::runtime_error("Joint array size changed between keys");for(size_t i=0;i<result.size();++i)result[i]=GfSlerp(weight,result[i],end[i]);return VtValue(result);}
      if(left.IsHolding<GfQuatf>())return VtValue(GfSlerp(weight,left.UncheckedGet<GfQuatf>(),right.UncheckedGet<GfQuatf>()));
      if(left.IsHolding<GfQuatd>())return VtValue(GfSlerp(weight,left.UncheckedGet<GfQuatd>(),right.UncheckedGet<GfQuatd>()));
      auto first=numericComponents(left),second=numericComponents(right);
      if(first.size()!=second.size())throw std::runtime_error("Animation tuple shape changed between keys");
      for(size_t i=0;i<first.size();++i)first[i]=first[i]*(1-weight)+second[i]*weight;
      return numericTuple(left,first);
    }
    if(target()->HasField(path,TfToken("default"),&left))return left;
    if(targetName.rfind("working:",0)==0)throw std::runtime_error("Selected source has no numeric opinion; edit the full tuple or choose its contributing mapping");
    if(!a.Get(&left,UsdTimeCode(time)))throw std::runtime_error("Cannot sample numeric attribute");return left;
  }
  std::vector<std::string> arrayLabels(const UsdAttribute &a,const VtValue &sample) {
    if(!numericArray(sample))return {};
    auto p=a.GetPrim();auto name=a.GetName().GetString();
    if(p.GetTypeName()!=TfToken("SkelAnimation") || (name!="translations" && name!="rotations" && name!="scales" && name!="blendShapeWeights"))
      throw std::runtime_error("Array authoring supports SkelAnimation joint and blend-shape channels only");
    bool weights=name=="blendShapeWeights";VtTokenArray names;
    if(!p.GetAttribute(TfToken(weights?"blendShapes":"joints")).Get(&names) || names.empty() || names.size()>64)
      throw std::runtime_error("Animation channels require a stable list of 1..64 joint or blend-shape names");
    size_t width=weights?1:name=="rotations"?4:3;auto values=numericComponents(sample);
    if(values.size()!=names.size()*width)throw std::runtime_error("Animation array does not match named channel topology");
    if((weights && !sample.IsHolding<VtFloatArray>()) || (name=="translations" && !sample.IsHolding<VtVec3fArray>()) ||
       (name=="rotations" && !sample.IsHolding<VtQuatfArray>()) || (name=="scales" && !sample.IsHolding<VtVec3hArray>()))
      throw std::runtime_error("Animation channel type differs from USD Skel schema");
    std::set<std::string> unique;std::vector<std::string> labels;
    for(const auto &entry:names){auto label=entry.GetString();if(label.empty() || label.size()>256 ||
      std::any_of(label.begin(),label.end(),[](unsigned char c){return c<32 || c==127;}) || !unique.insert(label).second)throw std::runtime_error("Invalid or duplicate animation channel name");
      for(size_t c=0;c<width;++c)labels.push_back(name+"["+label+"]"+(weights?"":"."+std::string(1,"xyzw"[c])));}
    return labels;
  }
  void editCurve(const Object &o,const std::string &op) {
    if(!o.count("time"))throw std::runtime_error("Curve edits require an explicit numeric stage time");
    auto a=prim(o).GetAttribute(TfToken(string(field(o,"name"))));
    if(!a || a.HasAuthoredConnections() || a.GetVariability()==SdfVariabilityUniform)throw std::runtime_error("Curve requires a varying unconnected numeric attribute");
    auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());
    if(a.HasSpline() || target()->HasField(path,TfToken("spline")))throw std::runtime_error("Spline editing requires an explicit bake; time-sample edits would lose tangent semantics");
    double time=sampleTime(o);seedSamples(a);
    if(op=="set_channel") {
      auto current=ownNumericSample(a,time);auto values=numericComponents(current);
      arrayLabels(a,current);
      double index=number(field(o,"channel"));
      if(index<0 || index>=values.size() || std::floor(index)!=index)throw std::runtime_error("Invalid numeric channel index");
      values[size_t(index)]=number(field(o,"value"));
      if(!a.Set(numericTuple(current,values),UsdTimeCode(time)))throw std::runtime_error("Cannot author numeric channel");
    }else {
      double from=number(field(o,"from_time"));if(std::abs(from)>1e9)throw std::runtime_error("Source key time exceeds supported range");
      VtValue key;
      if(!target()->QueryTimeSample(path,targetTime(from),&key) || !numericValue(key))throw std::runtime_error("No numeric key in the selected layer at the source time");
      arrayLabels(a,key);
      if(time==from)return;
      if(target()->QueryTimeSample(path,targetTime(time)))throw std::runtime_error("Destination key already exists; choose another time");
      if(!a.Set(key,UsdTimeCode(time)))throw std::runtime_error("Cannot copy numeric key");
      if(op=="move_key" && !a.ClearAtTime(UsdTimeCode(from)))throw std::runtime_error("Cannot remove moved key");
    }
  }
  JsValue curves(const Object &o) {
    auto p=prim(o,false);double time=sampleTime(o);JsArray curves;size_t total=0;
    for(auto a:p.GetAttributes()) {
      VtValue current;if(!a.Get(&current,UsdTimeCode(time)) || !numericValue(current))continue;
      auto attributeName=a.GetName().GetString();
      if(numericArray(current) && (p.GetTypeName()!=TfToken("SkelAnimation") ||
        (attributeName!="translations" && attributeName!="rotations" && attributeName!="scales" && attributeName!="blendShapeWeights")))continue;
      auto arrayNames=arrayLabels(a,current);
      auto components=numericComponents(current);size_t width=components.size();
      for(double v:components)if(!std::isfinite(v))throw std::runtime_error("Non-finite numeric curve value");
      auto count=a.GetNumTimeSamples();
      if(curves.size()+width>1024 || count>10000 || (total+=count*width)>100000)throw std::runtime_error("Curve inspector exceeds attribute/channel/key budget");
      auto spec=stage->GetEditTarget().MapToSpecPath(a.GetPath());
      std::string reason;
      if(p.IsInstanceProxy())reason="Instance proxies are read-only";
      else if(spec.IsEmpty())reason="Outside selected source edit context";
      else if(a.GetVariability()==SdfVariabilityUniform)reason="Uniform attributes cannot have keys";
      else if(a.HasAuthoredConnections())reason="Connected attributes are read-only";
      bool isSpline=a.HasSpline() || target()->HasField(spec,TfToken("spline")),splineEditable=false;
      if(isSpline && reason.empty()) {
        try {selectedSpline(a);splineScale();splineEditable=true;}catch(const std::exception &e){reason=e.what();}
        if(splineEditable)reason="Spline knots/tangents use spline tools; time-sample editing requires an explicit bake";
        else reason="Spline: "+reason;
      }
      std::vector<double> times;a.GetTimeSamples(&times);std::vector<std::vector<double>> values;
      if(isSpline && splineEditable){times.clear();auto mapping=stage->GetEditTarget().GetMapFunction().GetTimeOffset();for(const auto &k:selectedSpline(a).GetKnots())times.push_back(mapping*k.GetTime());}
      for(double t:times){if(!std::isfinite(t) || std::abs(t)>1e9)throw std::runtime_error("Curve time outside editable range");
        VtValue v;if(!a.Get(&v,UsdTimeCode(t)))throw std::runtime_error("Cannot read curve key");arrayLabels(a,v);auto tuple=numericComponents(v);
        if(tuple.size()!=width)throw std::runtime_error("Curve tuple width changed");for(double n:tuple)if(!std::isfinite(n))throw std::runtime_error("Non-finite curve key");values.push_back(tuple);}
      const std::string labels=a.GetTypeName().GetAsToken().GetString().rfind("color",0)==0?"rgba":"xyzw";
      for(size_t c=0;c<width;++c){JsArray keys;
        for(size_t i=0;i<times.size();++i)keys.emplace_back(Object{{"time",JsValue(times[i])},{"value",JsValue(values[i][c])},
          {"session",JsValue(stage->GetSessionLayer()->QueryTimeSample(a.GetPath(),times[i]))},
          {"authored_in_target",JsValue(!spec.IsEmpty() && target()->QueryTimeSample(spec,targetTime(times[i])))}});
        auto name=a.GetName().GetString();auto label=!arrayNames.empty()?arrayNames[c]:width==1?name:name+"["+labels[c]+"]";
        curves.emplace_back(Object{{"name",JsValue(name)},{"label",JsValue(label)},{"channel",JsValue(int(c))},{"width",JsValue(int(width))},
          {"type",JsValue(a.GetTypeName().GetAsToken().GetString())},{"value",JsValue(components[c])},{"keys",JsValue(keys)},
          {"editable",JsValue(reason.empty())},{"read_only_reason",JsValue(reason)},
          {"spline",JsValue(isSpline)},{"spline_editable",JsValue(splineEditable)},
          {"tuple_key_policy",JsValue(width==1?"scalar":"copy/move/delete affect the whole typed tuple; orientations normalize together")}});
      }
    }
    return JsValue(Object{{"path",JsValue(p.GetPath().GetString())},{"time",JsValue(time)},
      {"revision",JsValue(revision)},{"edit_target",JsValue(targetName)},{"curves",JsValue(curves)}});
  }
