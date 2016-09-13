:Evaluate: $oldContextPath = $ContextPath; $ContextPath = {"System`", "Global`"}; (* these are the only dependencies *)
:Evaluate: Begin@"InfiniTAM`Private`" (* create everythin in InfiniTAM`Private`* *)
:Evaluate: ClearAll@"InfiniTAM`Private`*" (* create everythin in InfiniTAM`Private`* *)

:Begin:
:Function:       createScene
:Pattern:        createScene[voxelSize_Real]
:Arguments:      { voxelSize }
:ArgumentTypes:  { Real }
:ReturnType:     Integer
:End:


:Begin:
:Function:       getSceneVoxelSize
:Pattern:        getSceneVoxelSize[id_Integer]
:Arguments:      { id }
:ArgumentTypes:  { Integer }
:ReturnType:     Real
:End:


:Begin:
:Function:       serializeScene
:Pattern:        serializeScene[id_Integer, fn_String]
:Arguments:      { id, fn }
:ArgumentTypes:  { Integer, String }
:ReturnType:     Manual
:End:


:Begin:
:Function:       deserializeScene
:Pattern:        deserializeScene[id_Integer, fn_String]
:Arguments:      { id, fn }
:ArgumentTypes:  { Integer, String }
:ReturnType:     Manual
:End:


:Begin:
:Function:       meshScene
:Pattern:        meshScene[id_Integer, fn_String]
:Arguments:      { id, fn }
:ArgumentTypes:  { Integer, String }
:ReturnType:     Manual
:End:


:Begin:
:Function:       initFineFromCoarse
:Pattern:        initFineFromCoarse[idFine_Integer, idCoarse_Integer] /; (idFine != idCoarse)
:Arguments:      { idFine, idCoarse }
:ArgumentTypes:  { Integer, Integer }
:ReturnType:     Manual
:End:


:Begin:
:Function:       computeArtificialLighting
:Pattern:        computeArtificialLighting[id_Integer, dir : {_,_,_}?numericVectorQ]
:Arguments:      { id, dir}
:ArgumentTypes:  { Integer, RealList }
:ReturnType:     Manual
:End:


:Begin:
:Function:       estimateLighting
:Pattern:        estimateLighting[id_Integer]
:Arguments:      { id }
:ArgumentTypes:  { Integer }
:ReturnType:     Manual
:End:


:Begin:
:Function:       buildSphereScene
:Pattern:        buildSphereScene[id_Integer, rad_Real]
:Arguments:      { id, rad }
:ArgumentTypes:  { Integer, Real }
:ReturnType:     Manual
:End:

:Begin:
:Function:       renderScene
:Pattern:        renderScene[
        sceneId_Integer, 
        shader_String,
        (* Manual *)
        poseWorldToView_?PoseMatrixQ,
        rgbIntrinsics : NamelessIntrinsicsPattern[]
    ]

:Arguments:      { sceneId, shader, poseWorldToView, rgbIntrinsics }
:ArgumentTypes:  { Integer, String, Manual }
:ReturnType:     Manual
:End:

:Begin:
:Function:       processFrame
:Pattern:        processFrame[doTracking : 0|1
    , sceneId_Integer
    (* Manual *)
    , rgbaByteImage_ /;TensorQ[rgbaByteImage, IntegerQ] && Last@Dimensions@rgbaByteImage == 4
    , depthData_?NumericMatrixQ
    , poseWorldToView_?PoseMatrixQ
    , intrinsicsRgb : NamelessIntrinsicsPattern[]
    , intrinsicsD : NamelessIntrinsicsPattern[]
    , rgbToDepth_?PoseMatrixQ
    ]
:Arguments:      { doTracking, sceneId, rgbaByteImage, depthData, poseWorldToView, intrinsicsRgb, intrinsicsD, rgbToDepth }
:ArgumentTypes:  { Integer, Integer, Manual }
:ReturnType:     Manual
:End:

:Begin:
:Function:       assertFalse
:Pattern:        assertFalse[]
:Arguments:      { }
:ArgumentTypes:  { }
:ReturnType:     Manual
:End:


:Begin:
:Function:       assertGPUFalse
:Pattern:        assertGPUFalse[]
:Arguments:      { }
:ArgumentTypes:  { }
:ReturnType:     Manual
:End:


:Evaluate: Protect@"InfiniTAM`Private`*"
:Evaluate: End[] 
:Evaluate: $ContextPath = $oldContextPath
