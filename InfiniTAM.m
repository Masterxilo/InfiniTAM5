(* Mathematica Package *)
(* Created by Mathematica Plugin for IntelliJ IDEA *)

(* :Title: InfiniTAM *)
(* :Context: InfiniTAM` *)
(* :Author: Paul *)
(* :Date: 2016-06-27 *)

(* :Package Version: 0.1 *)
(* :Mathematica Version: 10.2 *)
(* :Copyright: (c) 2016 Paul *)
(* :Keywords: *)
(* :Discussion: *)

BeginPackage["InfiniTAM`", {"Global`"}]


exports = {CreateScene
  , GetVoxelSize
 , SerializeScene
,DeserializeScene,MeshScene,BuildSphereScene,InitFineFromCoarse,ComputeArtificialLighting,EstimateLighting
  ,RGBDCamera,RGBDCameraPattern,CreateRGBDCamera,RenderScene,DepthImage, Shutdown, RGBDView
,CreateRGBDView, RGBDViewPattern, NamelessRGBDViewPattern, ProcessFrameAt, ProcessFrameTracking};


ProcessFrameTracking::usage = "
ProcessFrameTracking[scene, rgbdView]
ProcessFrameTracking[scene, rgbaImage, depthImage, RGBDCameraWithCurrentPoseGuess]
ProcessFrameTracking[scene, rgbdView, RGBDCameraWithCurrentPoseGuess]
";

DepthImage::usage = "Represents a 2D matrix of positive depth values in world-coordinates.
Missing values are set to 0. Values (distances in meters) are typically less than 4.

A matrix with this head is represented as an image with a color gradient scaling
from dark to bright with distance. Missing values are black.";
RGBDView

Begin["`Private`"]

ClearAll@@exports;

poseMatrixQ[x_] := NumericMatrixQ[x, {4, 4}];
IntrinsicsPattern[] := {fx_?NumericQ, fy_?NumericQ, cx_?NumericQ, cy_?NumericQ, w_Integer, h_Integer};
NamelessIntrinsicsPattern[] := {_?NumericQ, _?NumericQ, _?NumericQ, _?NumericQ, _Integer, _Integer};

Shutdown[] := (Quiet@Uninstall@link; link = Null);
link = Null;

CreateScene[Optional[voxelSize_?NumericQ, 0.005]] := (
  If[link === Null || Quiet@Check[LinkReadyQ@link,$Failed] === $Failed,
    link = Install@"J:\\Masterarbeit\\Implementation\\InfiniTAM5\\x64\\Debug\\InfiniTAM5.exe"]
  ;Scene@id /. id -> createScene@voxelSize
);

BuildSphereScene[Optional[rad_Real?Positive, 0.5], Optional[voxelSize_?NumericQ, 0.005]] := Module[
  {scene = CreateScene@voxelSize},
  BuildSphereScene[scene, rad]
  ; scene
];

DeserializeScene[filename_String] := Module[
  {scene = CreateScene[]},
  DeserializeScene[scene, filename]
  ; scene
];

BuildSphereScene[Scene[id_Integer], Optional[rad_Real?Positive, 0.5]] := buildSphereScene[id, rad];
DeserializeScene[Scene[id_Integer], filename_String] := deserializeScene[id, filename];


GetVoxelSize[Scene[id_Integer]] := getSceneVoxelSize@id;
SerializeScene[Scene[id_Integer], filename_String] := serializeScene[id, filename];
MeshScene[Scene[id_Integer], baseFilename_String] := meshScene[id, baseFilename];
MeshScene[scene : Scene[_Integer]] := (MeshScene[scene, "temp"]; Import["temp.obj"]);

InitFineFromCoarse[Scene[idFine_Integer], Scene[idCoarse_Integer]] /; (idFine != idCoarse) :=
    initFineFromCoarse[idFine, idCoarse];

ComputeArtificialLighting[Scene[id_Integer], dir : {_,_,_}?numericVectorQ] := computeArtificialLighting[id, dir];
EstimateLighting[Scene[id_Integer]] := estimateLighting[id];

RGBDCameraPattern[] = RGBDCamera@KeyValuePattern@{
    "poseWorldToView" -> poseWorldToView_?poseMatrixQ
  , "intrinsicsRgb" -> intrinsicsRgb : NamelessIntrinsicsPattern[]
  , "intrinsicsD" -> intrinsicsD : NamelessIntrinsicsPattern[]
  , "rgbToDepth" -> rgbToDepth_?poseMatrixQ
};

NamelessRGBDCameraPattern[] = RGBDCamera@KeyValuePattern@{
  "poseWorldToView" -> _?poseMatrixQ
  , "intrinsicsRgb" -> NamelessIntrinsicsPattern[]
  , "intrinsicsD" ->  NamelessIntrinsicsPattern[]
  , "rgbToDepth" -> _?poseMatrixQ
}

CreateRGBDCamera[
  (* extrinsic *)
    poseWorldToView_?poseMatrixQ
  (* RGBDCameraIntrinsics: *)
  , intrinsicsRgb : NamelessIntrinsicsPattern[]
  , intrinsicsD : NamelessIntrinsicsPattern[]
  , rgbToDepth_?poseMatrixQ
] := RGBDCamera@<|
    "poseWorldToView" -> poseWorldToView
  , "intrinsicsRgb" -> intrinsicsRgb
  , "intrinsicsD" -> intrinsicsD
  , "rgbToDepth" -> rgbToDepth
|>;

CreateRGBDCamera[Optional[poseWorldToView_?poseMatrixQ, IdentityMatrix@4], w_Integer : 1920, h_Integer : 1080] := Module[{intrin},
    intrin = {w,w, w/2, h/2, w, h};
    CreateRGBDCamera[poseWorldToView, intrin, intrin, IdentityMatrix@4]
  ];

RGBDViewPattern[] = RGBDView@KeyValuePattern@{
  "rgbImage" -> rgbImage_Image
  , "depthImage" -> depthImage : DepthImage[depthData_?NumericMatrixQ]
  , "RGBDCamera" -> rgbdCamera : RGBDCameraPattern[]
};

NamelessRGBDViewPattern[] = RGBDView@KeyValuePattern@{
  "rgbImage" -> _Image
  , "depthImage" ->  DepthImage[_?NumericMatrixQ]
  , "RGBDCamera" ->  NamelessRGBDCameraPattern[]
};

CreateRGBDView[
    rgbImage_Image
  , depthImage : DepthImage[depthData_?NumericMatrixQ]
  , rgbdCamera : RGBDCameraPattern[]
] := RGBDView@<|
  "rgbImage" -> rgbImage
  , "depthImage" -> depthImage
  , "RGBDCamera" -> rgbdCamera
|>;

(* renders from rgb camera, depth camera is ignored*)
RenderScene[
  Scene[id_Integer],
  Optional[RGBDCameraPattern[], CreateRGBDCamera[]],
  shader_String : "renderColour"
] := Module[{rgb, depth},
    {rgb, depth} = renderScene[id, shader, poseWorldToView, intrinsicsRgb];

    CreateRGBDView[
      Image[rgb, "Byte", ColorSpace -> "RGB"]
      ,DepthImage@depth
      ,CreateRGBDCamera[
          poseWorldToView
        , intrinsicsRgb
        , (*depth rendered from same perspective *) intrinsicsRgb
        , IdentityMatrix@4]
    ]
  ];

RenderScene[
  s : Scene[_Integer],
  poseWorldToView_?poseMatrixQ,
  shader_String : "renderColour"
] := RenderScene[s, CreateRGBDCamera@poseWorldToView, shader];

Unprotect[Dimensions, ImageDimensions,Image];

Dimensions[DepthImage[depthData_?NumericMatrixQ]] := Dimensions@depthData;
ImageDimensions[DepthImage[depthData_?NumericMatrixQ]] := Reverse@Dimensions@depthData;
Image[DepthImage[depthData_?NumericMatrixQ]] := Image@depthData;

Protect[Dimensions, ImageDimensions];

Format[DepthImage[depthData_?NumericMatrixQ]] := Module[{l},
    l = Select[Flatten@depthData, # > 0 &];
    ImageAdjust[Image@depthData, 0, {Min@l, Max@l}]
  ];

(* returns Null without tracking and estimatedNewPoseWorldToView, 4x4,
when tracking *)
ProcessFrame[doTracking : 0|1, Scene[id_Integer], rgbdView : RGBDViewPattern[]] := processFrame[
       doTracking
      ,id
      ,SetAlphaChannel@rgbImage~ImageData~"Byte"
      ,depthData
      ,poseWorldToView
      ,intrinsicsRgb
      ,intrinsicsD
      ,rgbToDepth
  ];

ProcessFrameAt[args__] := ProcessFrame[0, args];

RGBDCamera[data_Association][element_String] := data[[element]];
RGBDView[data_Association][element_String] := data[[element]];

ProcessFrameTracking[s : Scene[_Integer], rgbdView : NamelessRGBDViewPattern[]] := Module[
  {estimatedNewPoseWorldToView = ProcessFrame[1, s, rgbdView], c = First@rgbdView["RGBDCamera"]},
  (* update rgbdView's camera with new pose *)
  AssociateTo[c, "poseWorldToView" -> estimatedNewPoseWorldToView];
  RGBDCamera@c
  ];

ProcessFrameTracking[
  s : Scene[_Integer]
  , rgbImage_Image, depthImage : DepthImage[_?NumericMatrixQ]
  , rgbdCameraWithCurrentPoseGuess : NamelessRGBDCameraPattern[]] :=
      ProcessFrameTracking[s, CreateRGBDView[rgbImage, depthImage, rgbdCameraWithCurrentPoseGuess]];

ProcessFrameTracking[
  s : Scene[_Integer]
  , rgbdView : NamelessRGBDViewPattern[]
  (*overrides camera (position) of view*)
  , rgbdCameraWithCurrentPoseGuess : NamelessRGBDCameraPattern[]] :=
    ProcessFrameTracking[s, CreateRGBDView[rgbdView@"rgbImage", rgbdView@"depthImage", rgbdCameraWithCurrentPoseGuess]];

End[]

EndPackage[]