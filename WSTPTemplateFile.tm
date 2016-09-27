:Evaluate: $oldContextPath = $ContextPath; $ContextPath = {"System`", "Global`"}; (* these are the only dependencies *)
:Evaluate: Begin@"InfiniTAM`Private`" (* create everythin in InfiniTAM`Private`* *)
:Evaluate: UnprotectClearAll@"InfiniTAM`Private`*" (* create everythin in InfiniTAM`Private`* *)

:Begin:
:Function:       createScene
:Pattern:        createScene[voxelSize_Real]
:Arguments:      { voxelSize }
:ArgumentTypes:  { Real }
:ReturnType:     Integer
:End:


:Begin:
:Function:       getSceneVoxelSize
:Pattern:        getSceneVoxelSize[id_Integer?NonNegative]
:Arguments:      { id }
:ArgumentTypes:  { Integer }
:ReturnType:     Real
:End:


:Begin:
:Function:       serializeScene
:Pattern:        serializeScene[id_Integer?NonNegative, fn_String]
:Arguments:      { id, fn }
:ArgumentTypes:  { Integer, String }
:ReturnType:     Manual
:End:


:Begin:
:Function:       deserializeScene
:Pattern:        deserializeScene[id_Integer?NonNegative, fn_String]
:Arguments:      { id, fn }
:ArgumentTypes:  { Integer, String }
:ReturnType:     Manual
:End:


:Begin:
:Function:       countVoxelBlocks
:Pattern:        countVoxelBlocks[id_Integer?NonNegative]
:Arguments:      { id }
:ArgumentTypes:  { Integer }
:ReturnType:     Integer
:End:


:Begin:
:Function:       getVoxelBlock
:Pattern:        getVoxelBlock[id_Integer?NonNegative, i_Integer?Positive]
:Arguments:      { id, i }
:ArgumentTypes:  { Integer, Integer }
:ReturnType:     Manual
:End:

:Begin:
:Function:       putVoxelBlock
:Pattern:        putVoxelBlock[id_Integer?NonNegative, voxelBlockData : { {_,_,_} (*pos*), {__List} (*8^3 voxels' data*) }]
:Arguments:      { id, voxelBlockData }
:ArgumentTypes:  { Integer, Manual }
:ReturnType:     Manual
:End:

:Begin:
:Function:       meshScene
:Pattern:        meshScene[id_Integer?NonNegative, fn_String]
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
:Pattern:        computeArtificialLighting[id_Integer?NonNegative, dir : {_,_,_}?numericVectorQ]
:Arguments:      { id, dir}
:ArgumentTypes:  { Integer, RealList }
:ReturnType:     Manual
:End:


:Begin:
:Function:       estimateLighting
:Pattern:        estimateLighting[id_Integer?NonNegative]
:Arguments:      { id }
:ArgumentTypes:  { Integer }
:ReturnType:     Manual
:End:


:Begin:
:Function:       buildSphereScene
:Pattern:        buildSphereScene[id_Integer?NonNegative, rad_Real]
:Arguments:      { id, rad }
:ArgumentTypes:  { Integer, Real }
:ReturnType:     Manual
:End:

:Begin:
:Function:       renderScene
:Pattern:        renderScene[
        id_Integer?NonNegative, 
        shader_String,
        (* Manual *)
        poseWorldToView_?PoseMatrixQ,
        rgbIntrinsics : NamelessIntrinsicsPattern[]
    ]

:Arguments:      { id, shader, poseWorldToView, rgbIntrinsics }
:ArgumentTypes:  { Integer, String, Manual }
:ReturnType:     Manual
:End:

:Begin:
:Function:       processFrame
:Pattern:        processFrame[doTracking : 0|1
    , id_Integer?NonNegative
    (* Manual *)
    , rgbaByteImage_ /;TensorQ[rgbaByteImage, IntegerQ] && Last@Dimensions@rgbaByteImage == 4
    , depthData_?NumericMatrixQ
    , poseWorldToView_?PoseMatrixQ
    , intrinsicsRgb : NamelessIntrinsicsPattern[]
    , intrinsicsD : NamelessIntrinsicsPattern[]
    , rgbToDepth_?PoseMatrixQ
    ]
:Arguments:      { doTracking, id, rgbaByteImage, depthData, poseWorldToView, intrinsicsRgb, intrinsicsD, rgbToDepth }
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
