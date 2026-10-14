// Independent USD Skel evaluation: stage service edits are checked as real poses.
#include <pxr/pxr.h>
#include <pxr/base/js/json.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usd/primRange.h>
#include <pxr/usd/usdSkel/cache.h>
#include <pxr/usd/usdSkel/root.h>
#include <pxr/usd/usdSkel/skeletonQuery.h>
#include <pxr/usd/usdSkel/animQuery.h>
#include <iostream>
PXR_NAMESPACE_USING_DIRECTIVE
int main(int argc,char **argv) {
  if(argc!=3)return 1;auto stage=UsdStage::Open(argv[1]);if(!stage)return 2;
  UsdSkelCache cache;JsArray skeletons;
  for(auto p:stage->Traverse())if(p.IsA<UsdSkelRoot>())cache.Populate(UsdSkelRoot(p),UsdPrimDefaultPredicate);
  for(auto p:stage->Traverse())if(p.IsA<UsdSkelSkeleton>()) {
    auto query=cache.GetSkelQuery(UsdSkelSkeleton(p));VtMatrix4dArray transforms;VtFloatArray weights;
    if(!query || !query.ComputeJointSkelTransforms(&transforms,UsdTimeCode(std::stod(argv[2]))) ||
       !query.GetAnimQuery().ComputeBlendShapeWeights(&weights,UsdTimeCode(std::stod(argv[2]))))return 3;
    JsArray poses,blend;for(const auto &m:transforms){JsArray matrix;for(int r=0;r<4;++r)for(int c=0;c<4;++c)matrix.emplace_back(m[r][c]);poses.emplace_back(matrix);}for(float n:weights)blend.emplace_back(double(n));
    skeletons.emplace_back(JsObject{{"path",JsValue(p.GetPath().GetString())},{"joint_matrices",JsValue(poses)},{"weights",JsValue(blend)}});
  }
  if(skeletons.empty())return 4;JsWriter writer(std::cout);JsWriteValue(&writer,JsValue(skeletons));return 0;
}
