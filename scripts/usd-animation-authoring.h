// Session members. Scalar spline editing and whole-owned-workspace retiming.
  void supportedSpline(const TsSpline &s) {
    auto loop=s.GetInnerLoopParams();
    if(s.IsTimeValued() || loop.protoEnd>loop.protoStart || s.GetPreExtrapolation().mode>=TsExtrapLoopRepeat ||
       s.GetPostExtrapolation().mode>=TsExtrapLoopRepeat || s.GetCurveType()!=TsCurveTypeBezier ||
       (!s.IsHolding<float>() && !s.IsHolding<double>()))
      throw std::runtime_error("Spline profile requires non-looping float/double Bezier curves without time-valued values");
    auto map=s.GetKnots();std::vector<TsKnot> knots(map.begin(),map.end());if(knots.empty() || knots.size()>10000)throw std::runtime_error("Spline requires 1..10000 knots");
    for(size_t i=0;i<knots.size();++i) {
      const auto &k=knots[i];VtValue v,pre,post;k.GetValue(&v);k.GetPreTanSlope(&pre);k.GetPostTanSlope(&post);
      if(k.IsDualValued() || k.GetPreTanAlgorithm()!=TsTangentAlgorithmNone || k.GetPostTanAlgorithm()!=TsTangentAlgorithmNone)
        throw std::runtime_error("Dual values and automatic tangents require a separate bake workflow");
      for(double n:{k.GetTime(),number(value(v)),number(value(pre)),number(value(post)),k.GetPreTanWidth(),k.GetPostTanWidth()})
        if(!std::isfinite(n))throw std::runtime_error("Non-finite spline data");
      if(std::abs(k.GetTime())>1e9 || k.GetPreTanWidth()<0 || k.GetPostTanWidth()<0)
        throw std::runtime_error("Invalid spline time or tangent width");
      if(i+1<knots.size() && k.GetNextInterpolation()==TsInterpCurve &&
         k.GetPostTanWidth()+knots[i+1].GetPreTanWidth()>knots[i+1].GetTime()-k.GetTime())
        throw std::runtime_error("Bezier tangent widths must not cross inside a segment");
    }
  }
  UsdAttribute scalarAttribute(const Object &o,bool editable=true) {
    auto a=prim(o,editable).GetAttribute(TfToken(string(field(o,"name"))));VtValue v;
    if(!a || a.HasAuthoredConnections() || a.GetVariability()==SdfVariabilityUniform || !a.Get(&v,UsdTimeCode(sampleTime(o))) ||
       (!v.IsHolding<float>() && !v.IsHolding<double>()))throw std::runtime_error("Spline tools require a varying unconnected float/double scalar");
    return a;
  }
  TsSpline selectedSpline(const UsdAttribute &a) {
    VtValue v;auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());
    if(!target()->HasField(path,TfToken("spline"),&v) || !v.IsHolding<TsSpline>())
      throw std::runtime_error("Select the spline's contributing layer or explicitly author a new spline");
    auto s=v.UncheckedGet<TsSpline>();supportedSpline(s);return s;
  }
  double splineScale() {
    double scale=stage->GetEditTarget().GetMapFunction().GetTimeOffset().GetScale();
    if(!std::isfinite(scale) || scale<=0)throw std::runtime_error("Spline authoring requires a positive time mapping");return scale;
  }
  TsInterpMode interpolation(const std::string &mode) {
    if(mode=="held")return TsInterpHeld;if(mode=="linear")return TsInterpLinear;if(mode=="bezier")return TsInterpCurve;
    throw std::runtime_error("Interpolation must be held, linear or bezier");
  }
  std::string interpolationName(TsInterpMode mode) {
    return mode==TsInterpHeld?"held":mode==TsInterpLinear?"linear":"bezier";
  }
  void writeSpline(const UsdAttribute &a,const TsSpline &s) {
    supportedSpline(s);auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());
    // Establish an attribute spec through USD before writing layer-domain knots.
    if(!target()->HasSpec(path)){VtValue v;if(!a.Get(&v,UsdTimeCode(0)) || !a.Set(v))throw std::runtime_error("Cannot establish spline attribute");}
    target()->EraseField(path,TfToken("timeSamples"));target()->SetField(path,TfToken("spline"),VtValue(s));
  }
  JsValue splineInfo(const Object &o) {
    auto a=scalarAttribute(o,false);auto s=selectedSpline(a);double scale=splineScale();
    auto mapping=stage->GetEditTarget().GetMapFunction().GetTimeOffset();JsArray rows;
    for(const auto &k:s.GetKnots()) {VtValue v,pre,post;k.GetValue(&v);k.GetPreTanSlope(&pre);k.GetPostTanSlope(&post);
      rows.emplace_back(Object{{"time",JsValue(mapping*k.GetTime())},{"value",value(v)},
        {"interpolation",JsValue(interpolationName(k.GetNextInterpolation()))},{"in_slope",JsValue(number(value(pre))/scale)},
        {"out_slope",JsValue(number(value(post))/scale)},{"in_width",JsValue(k.GetPreTanWidth()*scale)},{"out_width",JsValue(k.GetPostTanWidth()*scale)}});
    }
    return JsValue(Object{{"path",JsValue(a.GetPrimPath().GetString())},{"name",JsValue(a.GetName().GetString())},{"knots",JsValue(rows)},
      {"edit_target",JsValue(targetName)},{"revision",JsValue(revision)}});
  }
  void retimeWorkspace(double rate) {
    if(workingLayers.empty())throw std::runtime_error("Rate conversion requires owned copies of the complete source graph");
    if(!sourceConflicts().empty())throw std::runtime_error("Resolve source conflicts before rate conversion");
    double old=stage->GetTimeCodesPerSecond(),factor=rate/old;
    if(rate<=0 || rate>1000 || !std::isfinite(factor) || factor<=0)throw std::runtime_error("Frame rate must be in (0,1000]");
    std::vector<SdfLayerRefPtr> layers{stage->GetSessionLayer()};for(auto &a:authorLayers)layers.push_back(a.layer);for(auto &w:workingLayers)layers.push_back(w.layer);
    size_t total=0;
    for(auto l:layers) {
      if((l->HasTimeCodesPerSecond() && l->GetTimeCodesPerSecond()!=old) || (l->HasFramesPerSecond() && l->GetFramesPerSecond()!=old))
        throw std::runtime_error("Mixed authored layer rates require an explicit import conversion");
      std::vector<SdfPath> paths;l->Traverse(SdfPath::AbsoluteRootPath(),[&](const SdfPath &p){paths.push_back(p);});
      if((total+=paths.size())>100000)throw std::runtime_error("Rate conversion exceeds spec budget");
      for(const auto &p:paths) {
        if(l->HasField(p,TfToken("clips")))throw std::runtime_error("Value clips are outside the rate conversion profile");
        for(auto f:l->ListFields(p)){VtValue v;l->HasField(p,f,&v);
          if(v.IsHolding<SdfTimeCode>() || v.IsHolding<VtArray<SdfTimeCode>>())throw std::runtime_error("Time-valued attributes are outside the rate conversion profile");}
        VtValue spline;if(l->HasField(p,TfToken("spline"),&spline)){if(!spline.IsHolding<TsSpline>())throw std::runtime_error("Invalid spline field");supportedSpline(spline.UncheckedGet<TsSpline>());}
      }
    }
    auto scaled=[&](double t){double n=t*factor;if(!std::isfinite(n) || std::abs(n)>1e9)throw std::runtime_error("Retimed time exceeds +/-1e9");return n;};
    SdfChangeBlock block;
    for(auto l:layers) {
      std::vector<SdfPath> paths;l->Traverse(SdfPath::AbsoluteRootPath(),[&](const SdfPath &p){paths.push_back(p);});
      for(const auto &p:paths) {
        VtValue v;
        if(l->HasField(p,TfToken("timeSamples"),&v)) {
          auto samples=v.Get<SdfTimeSampleMap>();if((total+=samples.size())>200000)throw std::runtime_error("Retiming exceeds sample budget");SdfTimeSampleMap changed;
          for(const auto &entry:samples){if(entry.second.IsHolding<SdfTimeCode>() || entry.second.IsHolding<VtArray<SdfTimeCode>>())throw std::runtime_error("Time-valued samples are unsupported");changed.emplace(scaled(entry.first),entry.second);}
          l->SetField(p,TfToken("timeSamples"),VtValue(changed));
        }
        if(l->HasField(p,TfToken("spline"),&v)) {
          auto s=v.Get<TsSpline>();TsSpline result(s.GetValueType());result.SetCurveType(s.GetCurveType());
          auto pre=s.GetPreExtrapolation(),post=s.GetPostExtrapolation();pre.slope/=factor;post.slope/=factor;result.SetPreExtrapolation(pre);result.SetPostExtrapolation(post);
          for(auto k:s.GetKnots()){VtValue a,b;k.GetPreTanSlope(&a);k.GetPostTanSlope(&b);k.SetTime(scaled(k.GetTime()));
            k.SetPreTanWidth(k.GetPreTanWidth()*factor);k.SetPostTanWidth(k.GetPostTanWidth()*factor);
            k.SetPreTanSlope(numericTuple(a,{number(value(a))/factor}));k.SetPostTanSlope(numericTuple(b,{number(value(b))/factor}));
            if(!result.SetKnot(k))throw std::runtime_error("Cannot retime spline knot");}
          supportedSpline(result);l->SetField(p,TfToken("spline"),VtValue(result));
        }
        auto offsets=[&](auto tag,const TfToken &fieldName){using T=decltype(tag);VtValue refs;if(!l->HasField(p,fieldName,&refs))return;auto list=refs.Get<SdfListOp<T>>();
          list.ModifyOperations([&](const T &item)->std::optional<T>{auto copy=item;auto offset=item.GetLayerOffset();copy.SetLayerOffset(SdfLayerOffset(scaled(offset.GetOffset()),offset.GetScale()));return copy;});l->SetField(p,fieldName,VtValue(list));};
        offsets(SdfReference(),TfToken("references"));offsets(SdfPayload(),TfToken("payload"));
      }
      auto offsets=l->GetSubLayerOffsets();for(size_t i=0;i<offsets.size();++i)l->SetSubLayerOffset(SdfLayerOffset(scaled(offsets[i].GetOffset()),offsets[i].GetScale()),i);
      if(l->HasStartTimeCode())l->SetStartTimeCode(scaled(l->GetStartTimeCode()));if(l->HasEndTimeCode())l->SetEndTimeCode(scaled(l->GetEndTimeCode()));
      l->SetTimeCodesPerSecond(rate);l->SetFramesPerSecond(rate);
    }
    // Mapped edit targets cache old time transforms; refresh after composition.
  }
  void animate(const Object &o,const std::string &op) {
    if(op=="convert_frame_rate") {
      retimeWorkspace(number(field(o,"rate")));if(targetName.rfind("working:",0)==0)selectWorking(targetName,targetContext,targetNode);else select(targetName);return;
    }
    auto a=scalarAttribute(o);auto path=stage->GetEditTarget().MapToSpecPath(a.GetPath());double scale=splineScale();VtValue prototype;
    if(!a.Get(&prototype,UsdTimeCode(sampleTime(o))))throw std::runtime_error("Cannot sample scalar property");
    if(op=="set_spline") {
      const auto &input=field(o,"knots");if(!input.IsArray() || input.GetJsArray().empty() || input.GetJsArray().size()>10000)throw std::runtime_error("Spline requires 1..10000 knots");
      TsSpline s;double previous=-std::numeric_limits<double>::infinity();
      for(const auto &row:input.GetJsArray()) {auto k=workspace::object(row);TsKnot knot(prototype.GetType());double time=number(field(k,"time"));
        if(std::abs(time)>1e9 || time<=previous)throw std::runtime_error("Spline times must increase within +/-1e9");previous=time;
        knot.SetTime(targetTime(time));knot.SetValue(numericInput(prototype,field(k,"value")));knot.SetNextInterpolation(interpolation(string(field(k,"interpolation"))));
        for(const std::string side:{"in","out"}){double slope=k.count(side+"_slope")?number(field(k,side+"_slope"))*scale:0;double width=k.count(side+"_width")?number(field(k,side+"_width"))/scale:0;
          if(side=="in"){knot.SetPreTanSlope(numericTuple(prototype,{slope}));knot.SetPreTanWidth(width);}else{knot.SetPostTanSlope(numericTuple(prototype,{slope}));knot.SetPostTanWidth(width);}}
        if(!s.SetKnot(knot))throw std::runtime_error("Cannot author spline knot");
      }
      writeSpline(a,s);return;
    }
    if(op=="set_interpolation") {
      auto mode=interpolation(string(field(o,"mode")));TsSpline s;VtValue existing;
      if(target()->HasField(path,TfToken("spline"),&existing))s=selectedSpline(a);
      else {
        if(a.HasSpline())throw std::runtime_error("Select the spline's contributing target");seedSamples(a);
        auto times=target()->ListTimeSamplesForPath(path);if(times.empty() || times.size()>10000)throw std::runtime_error("Interpolation requires 1..10000 selected-layer keys");
        for(double t:times){VtValue v;target()->QueryTimeSample(path,t,&v);TsKnot k(prototype.GetType());k.SetTime(t);k.SetValue(v);if(!s.SetKnot(k))throw std::runtime_error("Cannot convert time samples to spline");}
      }
      auto map=s.GetKnots();std::vector<TsKnot> knots(map.begin(),map.end());for(size_t i=0;i<knots.size();++i){auto k=knots[i];k.SetNextInterpolation(mode);
        if(mode==TsInterpCurve){k.SetPreTanWidth(i?(k.GetTime()-knots[i-1].GetTime())/3:0);k.SetPostTanWidth(i+1<knots.size()?(knots[i+1].GetTime()-k.GetTime())/3:0);}
        if(!s.SetKnot(k))throw std::runtime_error("Cannot set interpolation");}
      writeSpline(a,s);return;
    }
    auto s=selectedSpline(a);
    if(op=="set_spline_value" || op=="move_spline_key" || op=="copy_spline_key" || op=="delete_spline_key") {
      if(!o.count("time"))throw std::runtime_error("Spline key edits require an explicit time");
      double at=targetTime(sampleTime(o));TsKnot k;
      double from=(op=="move_spline_key" || op=="copy_spline_key")?targetTime(number(field(o,"from_time"))):at;
      if(!s.GetKnot(from,&k))throw std::runtime_error("No selected-layer spline knot at this time");
      if(op=="set_spline_value"){if(!k.SetValue(numericInput(prototype,field(o,"value"))) || !s.SetKnot(k))throw std::runtime_error("Cannot set spline value");}
      else if(op=="delete_spline_key"){if(s.GetKnots().size()<2)throw std::runtime_error("Cannot delete the last spline knot");s.RemoveKnot(at);}
      else {if(std::abs(from)>1e9)throw std::runtime_error("Source knot time outside supported range");if(from==at)return;TsKnot exists;
        if(s.GetKnot(at,&exists))throw std::runtime_error("Destination spline knot already exists");k.SetTime(at);
        if(op=="move_spline_key")s.RemoveKnot(from);if(!s.SetKnot(k))throw std::runtime_error("Cannot copy spline knot");}
      writeSpline(a,s);return;
    }
    if(op=="set_tangent") {
      if(!o.count("time"))throw std::runtime_error("Tangent edit requires a knot time");TsKnot k;
      if(!s.GetKnot(targetTime(sampleTime(o)),&k))throw std::runtime_error("No selected-layer spline knot at this time");
      auto side=string(field(o,"side"));double slope=number(field(o,"slope"))*scale,width=number(field(o,"width"))/scale;
      if(side=="in"){k.SetPreTanSlope(numericTuple(prototype,{slope}));k.SetPreTanWidth(width);}else if(side=="out"){k.SetPostTanSlope(numericTuple(prototype,{slope}));k.SetPostTanWidth(width);}else throw std::runtime_error("Tangent side must be in or out");
      if(!s.SetKnot(k))throw std::runtime_error("Cannot set tangent");writeSpline(a,s);return;
    }
    if(op!="bake_curve")throw std::runtime_error("Unknown animation operation");
    double start=number(field(o,"start")),end=number(field(o,"end")),step=number(field(o,"step")),error=number(field(o,"max_error"));
    if(start>=end || std::abs(start)>1e9 || std::abs(end)>1e9 || step<=0 || error<=0 || (end-start)/step>9999)
      throw std::runtime_error("Bake requires a finite ordered range, positive step/error and at most 10000 initial keys");
    auto map=s.GetKnots();std::vector<TsKnot> knots(map.begin(),map.end());for(size_t i=0;i+1<knots.size();++i)if(knots[i].GetNextInterpolation()==TsInterpHeld){VtValue x,y;knots[i].GetValue(&x);knots[i+1].GetValue(&y);if(x!=y)throw std::runtime_error("Discontinuous held curves require held runtime playback; linear baking is rejected");}
    size_t evaluations=0;auto evaluate=[&](double t){if(++evaluations>200000)throw std::runtime_error("Bake exceeds evaluation budget");double n;
      if(!s.Eval(targetTime(t),&n) || !std::isfinite(n))throw std::runtime_error("Cannot evaluate spline");return n;};
    std::map<double,double> samples;for(double t=start;t<end;t+=step){if(samples.size()>=10000 || t+step==t)throw std::runtime_error("Bake exceeds key budget");samples[t]=evaluate(t);}samples[end]=evaluate(end);
    auto mapping=stage->GetEditTarget().GetMapFunction().GetTimeOffset();for(const auto &k:knots){double t=mapping*k.GetTime();if(t>start && t<end)samples[t]=evaluate(t);}
    std::vector<std::pair<double,double>> pending;for(auto i=samples.begin(),j=std::next(i);j!=samples.end();++i,++j)pending.emplace_back(i->first,j->first);
    while(!pending.empty()){auto interval=pending.back();pending.pop_back();double lo=interval.first,hi=interval.second,largest=0;
      for(double w:{0.25,0.5,0.75}){double t=lo+(hi-lo)*w;largest=std::max(largest,std::abs(evaluate(t)-(samples.at(lo)*(1-w)+samples.at(hi)*w)));}
      if(largest>error/2){double mid=lo+(hi-lo)/2;if(mid==lo || mid==hi || samples.size()>=10000)throw std::runtime_error("Bake tolerance cannot be met within key budget");samples[mid]=evaluate(mid);pending.emplace_back(lo,mid);pending.emplace_back(mid,hi);}
    }
    // Finite dense validation, not a proof of continuous approximation error.
    for(auto i=samples.begin(),j=std::next(i);j!=samples.end();++i,++j)for(int n=1;n<32;++n){double w=n/32.0,t=i->first+(j->first-i->first)*w;
      if(std::abs(evaluate(t)-(i->second*(1-w)+j->second*w))>error)throw std::runtime_error("Bake failed dense sample validation");}
    SdfTimeSampleMap authored;for(const auto &entry:samples)authored.emplace(targetTime(entry.first),numericTuple(prototype,{entry.second}));
    target()->EraseField(path,TfToken("spline"));target()->SetField(path,TfToken("timeSamples"),VtValue(authored));
  }
