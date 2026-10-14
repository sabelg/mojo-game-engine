// Explicit, conservative conversion profile, not a MaterialX shader compiler.
#pragma once
#include <pxr/usd/usdShade/shader.h>
#include <pxr/base/js/json.h>
#include "usd-material-profile.h"
#include "usd-color.h"
PXR_NAMESPACE_USING_DIRECTIVE
static bool atlasEqual(const JsValue &a,const JsValue &b) {
  if((a.IsReal()||a.IsInt()) && (b.IsReal()||b.IsInt())) {
    auto x=a.IsReal()?a.GetReal():double(a.GetInt64());
    auto y=b.IsReal()?b.GetReal():double(b.GetInt64());
    return std::isfinite(x) && std::isfinite(y) && std::abs(x-y)<1e-6;
  }
  if(a.IsArray() && b.IsArray()) {
    const auto &x=a.GetJsArray(),&y=b.GetJsArray(); if(x.size()!=y.size()) return false;
    for(size_t i=0;i<x.size();++i) if(!atlasEqual(x[i],y[i])) return false; return true;
  }
  return a==b;
}
static JsValue atlasMaterialValue(const VtValue &v) {
  if(v.IsHolding<float>()) return JsValue(double(v.UncheckedGet<float>()));
  if(v.IsHolding<bool>()) return JsValue(v.UncheckedGet<bool>());
  if(v.IsHolding<GfVec3f>()) { auto x=v.UncheckedGet<GfVec3f>();
    return JsValue(JsArray{JsValue(double(x[0])),JsValue(double(x[1])),JsValue(double(x[2]))}); }
  return JsValue();
}
static bool atlasMaterial(UsdShadeShader shader,const TfToken &id,bool convert,JsArray &errors) {
  static const auto document=JsParseString(atlasMaterialProfiles);
  const auto &profiles=document.GetJsObject(); auto profile=profiles.find(id.GetString());
  if(profile==profiles.end()) return false;
  const auto &inputs=profile->second.GetJsObject().at("inputs").GetJsObject();
  const auto &mapping=profile->second.GetJsObject().at("mapping").GetJsObject();
  const auto prefix=shader.GetPath().GetString()+": ";
  size_t previous=errors.size();
  for(auto input:shader.GetInputs()) {
    auto name=input.GetBaseName().GetString(); auto def=inputs.find(name); VtValue v;
    if(def==inputs.end()) { errors.emplace_back(prefix+"unknown MaterialX input "+name); continue; }
    const auto space=input.GetAttr().GetColorSpace().GetString();
    if(input.HasConnectedSource() || input.GetAttr().ValueMightBeTimeVarying()) {
      errors.emplace_back(prefix+"MaterialX profile needs constant input "+name); continue;
    }
    if(!input.Get(&v)) continue;
    if(v.IsHolding<GfVec3f>() && !space.empty()) {
      try { v=VtValue(atlasLinearColor(v.UncheckedGet<GfVec3f>(),space)); }
      catch(const std::exception &error) { errors.emplace_back(prefix+"color conversion: "+error.what()); continue; }
    }
    auto actual=atlasMaterialValue(v); const auto &expected=def->second.GetJsObject().at("default");
    if(mapping.count(name)) {
      bool valid=actual.IsReal() || actual.IsArray();
      if(actual.IsReal()) valid=std::isfinite(actual.GetReal()) && actual.GetReal()>=0 && actual.GetReal()<=1;
      if(actual.IsArray()) for(auto c:actual.GetJsArray()) valid=valid && c.IsReal() && std::isfinite(c.GetReal()) && c.GetReal()>=0 && c.GetReal()<=1;
      if(!valid || actual.IsArray()!=expected.IsArray()) errors.emplace_back(prefix+"invalid MaterialX factor "+name);
    } else if(expected.IsNull() || !atlasEqual(actual,expected))
      errors.emplace_back(prefix+"bake unsupported MaterialX input "+name);
  }
  if(convert && errors.size()==previous) {
    for(const auto &entry:mapping) {
      const auto &def=inputs.at(entry.first).GetJsObject().at("default"); VtValue source;
      auto input=shader.GetInput(TfToken(entry.first)); if(input) input.Get(&source);
      if(def.IsArray()) {
        GfVec3f c; if(source.IsHolding<GfVec3f>()) c=atlasLinearColor(source.UncheckedGet<GfVec3f>(),input.GetAttr().GetColorSpace().GetString());
        else for(int i=0;i<3;++i) c[i]=float(def.GetJsArray()[i].GetReal());
        shader.CreateInput(TfToken(entry.second.GetString()),SdfValueTypeNames->Color3f).Set(c);
      } else {
        float f=source.IsHolding<float>()?source.UncheckedGet<float>():float(def.GetReal());
        shader.CreateInput(TfToken(entry.second.GetString()),SdfValueTypeNames->Float).Set(f);
      }
    }
    shader.GetIdAttr().Set(TfToken("UsdPreviewSurface"));
    shader.CreateOutput(TfToken("surface"),SdfValueTypeNames->Token);
  }
  return true;
}
