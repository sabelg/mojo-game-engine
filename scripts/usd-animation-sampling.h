// Offline conversion sampling. Preserve fractional authored keys on a bounded
// integer frame grid for Blender, with seconds retained through its frame rate.
static std::vector<double> atlasAncestorSampleTimes(const UsdPrim &prim,double start,double end) {
  std::set<double> times{start,end};
  for(double t=start;t<end;t+=1){times.insert(t);if(times.size()>16384)throw std::runtime_error("Animation sample grid exceeds 16384 keys");}
  for(auto p=prim;p && !p.IsPseudoRoot();p=p.GetParent())for(auto a:p.GetAttributes()) {
    if(a.GetNumTimeSamples()>10001)throw std::runtime_error("Animated attribute exceeds 10001 authored samples");
    std::vector<double> keys;a.GetTimeSamples(&keys);
    for(double t:keys)if(t>=start && t<=end){times.insert(t);if(times.size()>16384)throw std::runtime_error("Animated ancestor keys exceed 16384 samples");}
  }
  return std::vector<double>(times.begin(),times.end());
}
static int atlasConversionGridFactor(const UsdStageRefPtr &stage) {
  std::set<double> times{stage->GetStartTimeCode(),stage->GetEndTimeCode()};size_t entries=0;
  for(auto p:stage->Traverse())for(auto a:p.GetAttributes()) {
    if(a.HasSpline())throw std::runtime_error("Explicitly bake spline "+a.GetPath().GetString()+" before runtime conversion");
    if(a.GetTypeName()==SdfValueTypeNames->TimeCode || a.GetTypeName()==SdfValueTypeNames->TimeCodeArray)
      throw std::runtime_error("Time-valued attributes require an explicit conversion profile");
    std::vector<double> keys;a.GetTimeSamples(&keys);
    if((entries+=keys.size())>200000)throw std::runtime_error("Conversion exceeds authored key budget");
    for(double t:keys){if(!std::isfinite(t) || std::abs(t)>1e9)throw std::runtime_error("Invalid animation time");times.insert(t);}
  }
  // Decimal and binary fractional times share the smallest tested grid. Values
  // which need a finer grid reject; there is no silent rounding to whole frames.
  for(int factor=1;factor<=64;++factor){bool exact=true;
    for(double t:times)if(std::abs(t*factor-std::round(t*factor))>1e-7){exact=false;break;}
    if(exact)return factor;
  }
  throw std::runtime_error("Fractional keys require more than 64 conversion samples per source frame; explicitly bake to a supported grid");
}
static SdfLayerRefPtr atlasBakeConversionStage(const UsdStageRefPtr &source,int factor) {
  auto flattened=source->Flatten();auto stage=UsdStage::Open(flattened);stage->SetEditTarget(flattened);
  int64_t first=std::llround(source->GetStartTimeCode()*factor),last=std::llround(source->GetEndTimeCode()*factor);
  if(first<0 || last>1048574)throw std::runtime_error("Conversion frames are outside Blender profile [0,1048574]; explicitly shift the timeline");
  if(last<first || last-first>10000)throw std::runtime_error("Conversion frame grid exceeds 10001 samples per attribute");
  size_t evaluations=0,values=0;
  for(auto p:stage->Traverse())for(auto a:p.GetAttributes())if(a.ValueMightBeTimeVarying()) {
    std::vector<std::pair<double,VtValue>> samples;
    for(int64_t frame=first;frame<=last;++frame){VtValue value;
      if(++evaluations>200000 || !a.Get(&value,UsdTimeCode(double(frame)/factor)))throw std::runtime_error("Conversion sampling failed or exceeded 200000 evaluations");
      values+=value.IsArrayValued()?value.GetArraySize():1;if(values>2000000)throw std::runtime_error("Conversion exceeds two million sampled values");
      samples.emplace_back(double(frame),value);
    }
    if(!a.Clear())throw std::runtime_error("Cannot replace temporary animation samples");
    for(const auto &sample:samples)if(!a.Set(sample.second,UsdTimeCode(sample.first)))throw std::runtime_error("Cannot author temporary conversion sample");
  }
  stage->SetStartTimeCode(first);stage->SetEndTimeCode(last);
  stage->SetTimeCodesPerSecond(source->GetTimeCodesPerSecond()*factor);stage->SetFramesPerSecond(source->GetTimeCodesPerSecond()*factor);
  std::string text;flattened->ExportToString(&text);if(text.size()>64*1024*1024)throw std::runtime_error("Sampled conversion stage exceeds 64 MiB");
  return flattened;
}
