// Convert an OpenUSD camera into Atlas's Y-up/metre, column-vector convention.
// Gf stores row-vector matrices; its row-major scalar order is Atlas column-major.
#pragma once
#include <pxr/usd/usdGeom/camera.h>
#include <pxr/usd/usdGeom/metrics.h>
#include <pxr/base/gf/camera.h>
#include <pxr/base/gf/frustum.h>
#include <pxr/base/js/json.h>
#include <cmath>
#include <stdexcept>
PXR_NAMESPACE_USING_DIRECTIVE
static JsValue atlasMatrix(const GfMatrix4d &m) {
  JsArray a;
  for(int r=0;r<4;++r) for(int c=0;c<4;++c) {
    if(!std::isfinite(m[r][c])) throw std::runtime_error("Non-finite camera matrix");
    a.emplace_back(m[r][c]);
  }
  return JsValue(a);
}
static JsValue atlasCamera(const UsdPrim &prim, double time) {
  UsdGeomCamera schema(prim);
  auto camera=schema.GetCamera(UsdTimeCode(time));
  auto stage=prim.GetStage();
  const double units=UsdGeomGetStageMetersPerUnit(stage);
  if(!std::isfinite(units)||units<=0) throw std::runtime_error("Invalid camera stage units");
  auto world=schema.ComputeLocalToWorldTransform(UsdTimeCode(time));
  if(UsdGeomGetStageUpAxis(stage)==UsdGeomTokens->z) {
    GfMatrix4d rotate(1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1);
    world=world*rotate;
  }
  for(int i=0;i<3;++i) world[3][i]*=units;
  if(std::abs(world.GetDeterminant())<1e-12) throw std::runtime_error("Singular camera transform");
  camera.SetTransform(world);
  camera.SetHorizontalAperture(camera.GetHorizontalAperture()*units);
  camera.SetVerticalAperture(camera.GetVerticalAperture()*units);
  camera.SetHorizontalApertureOffset(camera.GetHorizontalApertureOffset()*units);
  camera.SetVerticalApertureOffset(camera.GetVerticalApertureOffset()*units);
  camera.SetFocalLength(camera.GetFocalLength()*units);
  auto clip=camera.GetClippingRange();
  camera.SetClippingRange(GfRange1f(clip.GetMin()*units,clip.GetMax()*units));
  if(camera.GetHorizontalAperture()<=0||camera.GetVerticalAperture()<=0||camera.GetFocalLength()<=0||
     clip.GetMin()<=0||clip.GetMax()<=clip.GetMin()) throw std::runtime_error("Invalid camera optics or clipping range");
  for(const auto &name:{"exposure:iso","exposure:time","exposure:responsivity","exposure:fStop","exposure"}) {
    float value=0;if(!schema.GetPrim().GetAttribute(TfToken(name)).Get(&value,UsdTimeCode(time)))throw std::runtime_error("Invalid physical camera attribute type");
    if(!std::isfinite(value) || (std::string(name)=="exposure"?std::abs(value)>64:value<0) || (std::string(name)=="exposure:fStop" && value==0))throw std::runtime_error("Invalid physical camera exposure inputs");
  }
  double exposure=schema.ComputeLinearExposureScale(UsdTimeCode(time));
  if(!std::isfinite(exposure)||exposure<0||exposure>1000000)throw std::runtime_error("Camera exposure scale outside 0..1000000 runtime profile");
  auto frustum=camera.GetFrustum();
  return JsValue(JsObject{{"id",JsValue(prim.GetPath().GetString())},{"time",JsValue(time)},
    {"exposure_scale",JsValue(exposure)}, {"world",atlasMatrix(world)},{"view",atlasMatrix(frustum.ComputeViewMatrix())},
    {"projection",atlasMatrix(frustum.ComputeProjectionMatrix())},
    {"projection_type",JsValue(camera.GetProjection()==GfCamera::Perspective?"perspective":"orthographic")},
    {"aspect",JsValue(double(camera.GetHorizontalAperture()/camera.GetVerticalAperture()))},
    {"policy",JsValue("Y-up metres; sample at stated USD time; authored aperture aspect; OpenGL depth convention")}});
}
