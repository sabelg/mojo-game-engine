// Generate a real pinned-OpenUSD spline fixture for authoring rejection checks.
#include <pxr/pxr.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usd/attribute.h>
#include <pxr/base/ts/spline.h>
#include <pxr/base/ts/knot.h>
PXR_NAMESPACE_USING_DIRECTIVE
int main(int argc,char **argv) {
  if(argc!=2)return 1;
  auto stage=UsdStage::CreateInMemory();auto prim=stage->DefinePrim(SdfPath("/Animated"));
  auto attribute=prim.CreateAttribute(TfToken("curve"),SdfValueTypeNames->Double);
  TsSpline spline;
  for(int i=0;i<2;++i){TsKnot knot;knot.SetTime(i*10);knot.SetValue(double(i*20));
    knot.SetNextInterpolation(TsInterpCurve);knot.SetPreTanWidth(2);knot.SetPostTanWidth(2);
    knot.SetPreTanSlope(0.0);knot.SetPostTanSlope(0.0);if(!spline.SetKnot(knot))return 2;}
  if(!attribute.SetSpline(spline) || !attribute.HasSpline())return 3;
  return stage->GetRootLayer()->Export(argv[1])?0:4;
}
