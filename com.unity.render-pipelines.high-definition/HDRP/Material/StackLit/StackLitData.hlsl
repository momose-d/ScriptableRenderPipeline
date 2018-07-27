//-------------------------------------------------------------------------------------
// Fill SurfaceData/Builtin data function
//-------------------------------------------------------------------------------------
#include "CoreRP/ShaderLibrary/Sampling/SampleUVMapping.hlsl"
#include "HDRP/Material/MaterialUtilities.hlsl"

//-----------------------------------------------------------------------------
// Texture Mapping
//-----------------------------------------------------------------------------

// Normal Map Filtering:
// Config set according to settings in the importer (see C# code NormalMapAverageLengthTexturePostprocessor.cs).
#define NORMALMAP_USES_VARIANCE // define if the importer is set to generate variance directly.
#define NORMALMAP_LOWEST_AVERAGE_NORMAL_LENGTH 0.8695
#define NORMALMAP_HIGHEST_VARIANCE 0.03125

#ifdef NORMALMAP_USES_VARIANCE
#define NORMALMAP_NEUTRAL_DISPERSION_VALUE 0.0
#else
#define NORMALMAP_NEUTRAL_DISPERSION_VALUE 1.0
#endif

#define TEXCOORD_INDEX_UV0          (0)
#define TEXCOORD_INDEX_UV1          (1)
#define TEXCOORD_INDEX_UV2          (2)
#define TEXCOORD_INDEX_UV3          (3)
#define TEXCOORD_INDEX_PLANAR_XY    (4)
#define TEXCOORD_INDEX_PLANAR_YZ    (5)
#define TEXCOORD_INDEX_PLANAR_ZX    (6)
#define TEXCOORD_INDEX_TRIPLANAR    (7)
#define TEXCOORD_INDEX_COUNT        (TEXCOORD_INDEX_TRIPLANAR) // Triplanar is not consider as having mapping

struct TextureUVMapping
{
    float2 texcoords[TEXCOORD_INDEX_COUNT][2];
#ifdef _MAPPING_TRIPLANAR
    float3 triplanarWeights[2];
#endif

    float3 vertexNormalWS;
    float3 vertexTangentWS[4];
    float3 vertexBitangentWS[4];
};

void InitializeMappingData(FragInputs input, out TextureUVMapping uvMapping)
{
    float2 uvXZ;
    float2 uvXY;
    float2 uvZY;

    // Build the texcoords array.
    uvMapping.texcoords[TEXCOORD_INDEX_UV0][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV0][1] = input.texCoord0.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV1][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV1][1] = input.texCoord1.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV2][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV2][1] = input.texCoord2.xy;
    uvMapping.texcoords[TEXCOORD_INDEX_UV3][0] = uvMapping.texcoords[TEXCOORD_INDEX_UV3][1] = input.texCoord3.xy;

    // planar/triplanar
    GetTriplanarCoordinate(GetAbsolutePositionWS(input.positionRWS), uvXZ, uvXY, uvZY);
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_XY][0] = uvXY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_YZ][0] = uvZY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_ZX][0] = uvXZ;

    // If we use local planar mapping, convert to local space
    GetTriplanarCoordinate(TransformWorldToObject(input.positionRWS), uvXZ, uvXY, uvZY);
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_XY][1] = uvXY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_YZ][1] = uvZY;
    uvMapping.texcoords[TEXCOORD_INDEX_PLANAR_ZX][1] = uvXZ;

#ifdef _MAPPING_TRIPLANAR
    float3 vertexNormal = input.worldToTangent[2].xyz;
    uvMapping.triplanarWeights[0] = ComputeTriplanarWeights(vertexNormal);
    // If we use local planar mapping, convert to local space
    vertexNormal = TransformWorldToObjectDir(vertexNormal);
    uvMapping.triplanarWeights[1] = ComputeTriplanarWeights(vertexNormal);
#endif

    // Normal mapping with surface gradient
    float3 vertexNormalWS = input.worldToTangent[2];
    uvMapping.vertexNormalWS = vertexNormalWS;

    uvMapping.vertexTangentWS[0] = input.worldToTangent[0];
    uvMapping.vertexBitangentWS[0] = input.worldToTangent[1];

    float3 dPdx = ddx_fine(input.positionRWS);
    float3 dPdy = ddy_fine(input.positionRWS);

    float3 sigmaX = dPdx - dot(dPdx, vertexNormalWS) * vertexNormalWS;
    float3 sigmaY = dPdy - dot(dPdy, vertexNormalWS) * vertexNormalWS;
    //float flipSign = dot(sigmaY, cross(vertexNormalWS, sigmaX) ) ? -1.0 : 1.0;
    float flipSign = dot(dPdy, cross(vertexNormalWS, dPdx)) < 0.0 ? -1.0 : 1.0; // gives same as the commented out line above

    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord1, uvMapping.vertexTangentWS[1], uvMapping.vertexBitangentWS[1]);
    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord2, uvMapping.vertexTangentWS[2], uvMapping.vertexBitangentWS[2]);
    SurfaceGradientGenBasisTB(vertexNormalWS, sigmaX, sigmaY, flipSign, input.texCoord3, uvMapping.vertexTangentWS[3], uvMapping.vertexBitangentWS[3]);
}

float4 SampleTexture2DScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, TextureUVMapping uvMapping)
{
    return SAMPLE_TEXTURE2D(textureName, samplerName, (uvMapping.texcoords[textureNameUV][textureNameUVLocal] * textureNameST.xy + textureNameST.zw));
}

float4 SampleTexture2DScaleBiasLod(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, float lod, TextureUVMapping uvMapping)
{
    return SAMPLE_TEXTURE2D_LOD(textureName, samplerName, (uvMapping.texcoords[textureNameUV][textureNameUVLocal] * textureNameST.xy + textureNameST.zw), lod);
}

// If we use triplanar on any of the properties, then we enable the triplanar path
float4 SampleTexture2DTriplanarScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, TextureUVMapping uvMapping)
{
#ifdef _MAPPING_TRIPLANAR
    if (textureNameUV == TEXCOORD_INDEX_TRIPLANAR)
    {
        float4 val = float4(0.0, 0.0, 0.0, 0.0);

        if (uvMapping.triplanarWeights[textureNameUVLocal].x > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].x * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_YZ, textureNameUVLocal, textureNameST, uvMapping);
        if (uvMapping.triplanarWeights[textureNameUVLocal].y > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].y * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_ZX, textureNameUVLocal, textureNameST, uvMapping);
        if (uvMapping.triplanarWeights[textureNameUVLocal].z > 0.0)
            val += uvMapping.triplanarWeights[textureNameUVLocal].z * SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_XY, textureNameUVLocal, textureNameST, uvMapping);

        return val;
    }
    else
    {
#endif // _MAPPING_TRIPLANAR
        return SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
#ifdef _MAPPING_TRIPLANAR
    }
#endif
}

float4 SampleTexture2DTriplanarNormalScaleBias(TEXTURE2D_ARGS(textureName, samplerName), float textureNameUV, float textureNameUVLocal, float4 textureNameST, float textureNameObjSpace, TextureUVMapping uvMapping, float scale)
{
    if (textureNameObjSpace)
    {
        // TODO: obj triplanar (need to do * 2 - 1 before blending)

        // We forbid scale in case of object space as it make no sense
        // Decompress normal ourselve
        float4 packedNormal = SampleTexture2DTriplanarScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
        float3 normalOS = packedNormal.xyz * 2.0 - 1.0;
        float normalDispersionMeasure = packedNormal.w; // If we used a object space normal map that store average normal, the formap is RGB (normal xyz) and A (a measure of normal dispersion: ie variance or the average normal's length)
        // no need to renormalize normalOS for SurfaceGradientFromPerturbedNormal
        return float4(SurfaceGradientFromPerturbedNormal(uvMapping.vertexNormalWS, TransformObjectToWorldDir(normalOS)), normalDispersionMeasure);
    }
    else
    {
#ifdef _MAPPING_TRIPLANAR
        if (textureNameUV == TEXCOORD_INDEX_TRIPLANAR)
        {
            float2 derivXplane;
            float2 derivYPlane;
            float2 derivZPlane;
            derivXplane = derivYPlane = derivZPlane = float2(0.0, 0.0);
            float normalDispersionMeasure = 0.0;

            if (uvMapping.triplanarWeights[textureNameUVLocal].x > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_YZ, textureNameUVLocal, textureNameST, uvMapping);
                normalDispersionMeasure += uvMapping.triplanarWeights[textureNameUVLocal].x * packedNormal.z;
                derivXplane = uvMapping.triplanarWeights[textureNameUVLocal].x * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }
            if (uvMapping.triplanarWeights[textureNameUVLocal].y > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_ZX, textureNameUVLocal, textureNameST, uvMapping);
                normalDispersionMeasure += uvMapping.triplanarWeights[textureNameUVLocal].y * packedNormal.z;
                derivYPlane = uvMapping.triplanarWeights[textureNameUVLocal].y * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }
            if (uvMapping.triplanarWeights[textureNameUVLocal].z > 0.0)
            {
                float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), TEXCOORD_INDEX_PLANAR_XY, textureNameUVLocal, textureNameST, uvMapping);
                normalDispersionMeasure += uvMapping.triplanarWeights[textureNameUVLocal].z * packedNormal.z;
                derivZPlane = uvMapping.triplanarWeights[textureNameUVLocal].z * UnpackDerivativeNormalRGorAG(packedNormal, scale);
            }

            // Assume derivXplane, derivYPlane and derivZPlane sampled using (z,y), (z,x) and (x,y) respectively.
            float3 volumeGrad = float3(derivZPlane.x + derivYPlane.y, derivZPlane.y + derivXplane.y, derivXplane.x + derivYPlane.x);
            return float4(SurfaceGradientFromVolumeGradient(uvMapping.vertexNormalWS, volumeGrad), normalDispersionMeasure);
        }
#endif

        float4 packedNormal = SampleTexture2DScaleBias(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, uvMapping);
        //float4 packedNormal = SampleTexture2DScaleBiasLod(TEXTURE2D_PARAM(textureName, samplerName), textureNameUV, textureNameUVLocal, textureNameST, 1.0, uvMapping);
        float normalDispersionMeasure = packedNormal.z; // If we used a tangent space normal map that store a measure of normal dispersion, the formap is RG (normal xy) and B (normal dispersion: ie variance or the average normal's length)
        float2 deriv = UnpackDerivativeNormalRGorAG(packedNormal, scale);

        if (textureNameUV <= TEXCOORD_INDEX_UV3)
        {
            return float4(SurfaceGradientFromTBN(deriv, uvMapping.vertexTangentWS[textureNameUV], uvMapping.vertexBitangentWS[textureNameUV]), normalDispersionMeasure);
        }
        else
        {
            float3  volumeGrad;
            if (textureNameUV == TEXCOORD_INDEX_PLANAR_YZ)
                volumeGrad = float3(0.0, deriv.y, deriv.x);
            else if (textureNameUV == TEXCOORD_INDEX_PLANAR_ZX)
                volumeGrad = float3(deriv.y, 0.0, deriv.x);
            else if (textureNameUV == TEXCOORD_INDEX_PLANAR_XY)
                volumeGrad = float3(deriv.x, deriv.y, 0.0);

            return float4(SurfaceGradientFromVolumeGradient(uvMapping.vertexNormalWS, volumeGrad), normalDispersionMeasure);
        }
    }
}

#define SAMPLE_TEXTURE2D_SCALE_BIAS(name) SampleTexture2DTriplanarScaleBias(name, sampler##name, name##UV, name##UVLocal, name##_ST, uvMapping)
#define SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(name, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, sampler##name, name##UV, name##UVLocal, name##_ST, objSpace, uvMapping, scale)
#define SAMPLE_TEXTURE2D_NORMAL_PROPNAME_SCALE_BIAS(name, propname, scale, objSpace) SampleTexture2DTriplanarNormalScaleBias(name, sampler##propname, propname##UV, propname##UVLocal, propname##_ST, objSpace, uvMapping, scale)
//...permits referencing all properties from another texture name

#define SAMPLE_TEXTURE2D_SCALE_BIAS_LOD(name, lod) SampleTexture2DScaleBiasLod(name, sampler##name, name##UV, name##UVLocal, name##_ST, lod, uvMapping) // for testing


float DecodeNormalDispersionMeasureToVariance(float gradientW)
{
    // These depend on the importer settings, keep in synch.
#ifdef NORMALMAP_USES_VARIANCE
    bool normalMapHasVarianceEncoded = true; // normalMap has variance encoded or averageNormalLength ?
#else
    bool normalMapHasVarianceEncoded = false;
#endif
    float lowestAverageNormalLengthAllowed = NORMALMAP_LOWEST_AVERAGE_NORMAL_LENGTH;
    float highestVarianceAllowed = NORMALMAP_HIGHEST_VARIANCE;

    float variance = 0.0;

    if (normalMapHasVarianceEncoded)
    {
        variance = gradientW * highestVarianceAllowed;
    }
    else
    {
        variance = TextureNormalVariance( gradientW * (1.0 - lowestAverageNormalLengthAllowed) + lowestAverageNormalLengthAllowed );
    }
    return variance;
}

float4 AddDetailGradient(float4 gradient, float4 detailGradient, float detailMask)
{
#ifdef NORMALMAP_USES_VARIANCE
    bool normalMapHasVarianceEncoded = true; // normalMap has variance encoded or averageNormalLength ?
#else
    bool normalMapHasVarianceEncoded = false;
#endif

    gradient.xyz += detailGradient.xyz * detailMask;

    if (_TextureNormalFilteringEnabled > 0.0)
    {
        if (normalMapHasVarianceEncoded)
        {
            // Note: we haven't decoded the range of the encoded variance yet, but their real
            // range is the same, so these values between [0,1] can still be added together.
            // We saturate because even though variance is not bounded, we thresholded it
            // to do the range encoding in the importer so saturate here to be consistent.
            // (see C# code NormalMapAverageLengthTexturePostprocessor.cs).
            // Add variances together, but the modulating scalar "detailMask" is squared.
            gradient.w = saturate(gradient.w + detailGradient.w * detailMask * detailMask);
        }
        else
        {
            // Here, we will assume the averageNormalLength is > 0.6 and thus in a
            // region approximately linear in relation to variance (in lower ranges, the
            // relationship become quite nonlinear. Obviously even without looking at the
            // the vMF fit function, variance is unbounded but the length can only go to zero)
            // Note that a gradient.w = 0 means an averageNormalLength = lowestAverageNormalLengthAllowed
            // here since the value is still range encoded at this point.
            // (see C# importer code comments for details).
            gradient.w = saturate(gradient.w - (1.0 - detailGradient.w) * detailMask * detailMask);
        }
    }
    return gradient;
}


//-----------------------------------------------------------------------------
// GetSurfaceAndBuiltinData
//-----------------------------------------------------------------------------

//
// cf with
//    LitData.hlsl:GetSurfaceAndBuiltinData()
//    LitDataIndividualLayer.hlsl:GetSurfaceData( )
//    LitBuiltinData.hlsl:GetBuiltinData()
//
// Here we can combine them
//
void GetSurfaceAndBuiltinData(FragInputs input, float3 V, inout PositionInputs posInput, out SurfaceData surfaceData, out BuiltinData builtinData)
{
    ApplyDoubleSidedFlipOrMirror(input); // Apply double sided flip on the vertex normal.

    TextureUVMapping uvMapping; // Note this identifier is directly referenced in the SAMPLE_TEXTURE2D_* macros above
    InitializeMappingData(input, uvMapping);

    // -------------------------------------------------------------
    // Surface Data
    // -------------------------------------------------------------

    float alpha = SAMPLE_TEXTURE2D_SCALE_BIAS(_BaseColorMap).a * _BaseColor.a;
#ifdef _ALPHATEST_ON
    //NEWLITTODO: Once we include those passes in the main StackLit.shader, add handling of CUTOFF_TRANSPARENT_DEPTH_PREPASS and _POSTPASS
    // and the related properties (in the .shader) and uniforms (in the StackLitProperties file) _AlphaCutoffPrepass, _AlphaCutoffPostpass
    DoAlphaTest(alpha, _AlphaCutoff);
#endif

    // These static material feature allow compile time optimization
    surfaceData.materialFeatures = MATERIALFEATUREFLAGS_STACK_LIT_STANDARD;

    // Standard
    surfaceData.baseColor = SAMPLE_TEXTURE2D_SCALE_BIAS(_BaseColorMap).rgb * _BaseColor.rgb;

    float4 gradient = float4(0.0, 0.0, 0.0, NORMALMAP_NEUTRAL_DISPERSION_VALUE);
    if (_NormalUseMap)
    {
        gradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_NormalMap, _NormalScale, _NormalMapObjSpace);
    }

    float4 bentGradient = float4(0.0, 0.0, 0.0, NORMALMAP_NEUTRAL_DISPERSION_VALUE);
    // ...last value is for normal map filtering (average normal length). Unused for bent normal for now, but
    // could be used to tilt back the bent normal to the normal and/or enlarge the visibility cone as bent visibility
    // can alias like everything else.
    // TODO
#ifdef _BENTNORMALMAP
    bentGradient = SAMPLE_TEXTURE2D_NORMAL_PROPNAME_SCALE_BIAS(_BentNormalMap, _NormalMap, _NormalScale, _NormalMapObjSpace);
#endif

    surfaceData.perceptualSmoothnessA = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_SmoothnessAMap), _SmoothnessAMapChannelMask);
    surfaceData.perceptualSmoothnessA = lerp(_SmoothnessAMapRange.x, _SmoothnessAMapRange.y, surfaceData.perceptualSmoothnessA);
    surfaceData.perceptualSmoothnessA = lerp(_SmoothnessA, surfaceData.perceptualSmoothnessA, _SmoothnessAUseMap);

    // Metallic / specular color
    surfaceData.dielectricIor = _DielectricIor; // shouldn't be needed if _MATERIAL_FEATURE_SPECULAR_COLOR
    // debug test, to visualize the dispersion measure of the normal map:
    //surfaceData.dielectricIor = gradient.w;
    surfaceData.specularColor = float3(1.0, 1.0, 1.0);
    surfaceData.metallic = 0.0;
#ifdef _MATERIAL_FEATURE_SPECULAR_COLOR
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_SPECULAR_COLOR;
    
    surfaceData.specularColor = SAMPLE_TEXTURE2D_SCALE_BIAS(_SpecularColorMap).rgb * _SpecularColor.rgb;
    // Reproduce the energy conservation done in legacy Unity. Not ideal but better for compatibility and users can unchek it
    surfaceData.baseColor *= _EnergyConservingSpecularColor > 0.0 ? (1.0 - Max3(surfaceData.specularColor.r, surfaceData.specularColor.g, surfaceData.specularColor.b)) : 1.0;
#else
    surfaceData.metallic = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_MetallicMap), _MetallicMapChannelMask);
    surfaceData.metallic = lerp(_MetallicMapRange.x, _MetallicMapRange.y, surfaceData.metallic);
    surfaceData.metallic = lerp(_Metallic, surfaceData.metallic, _MetallicUseMap);
#endif

    // Ambient Occlusion
    surfaceData.ambientOcclusion = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_AmbientOcclusionMap), _AmbientOcclusionMapChannelMask);
    surfaceData.ambientOcclusion = lerp(_AmbientOcclusionMapRange.x, _AmbientOcclusionMapRange.y, surfaceData.ambientOcclusion);
    surfaceData.ambientOcclusion = lerp(_AmbientOcclusion, surfaceData.ambientOcclusion, _AmbientOcclusionUseMap);

    // Dual specular lobe
    surfaceData.lobeMix = 0.0;
    surfaceData.perceptualSmoothnessB = 1.0;
    surfaceData.haziness = 0.0;
    surfaceData.hazeExtent = 0.0;
    surfaceData.hazyGlossMaxDielectricF0 = 1.0;

#ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_DUAL_SPECULAR_LOBE;
#ifdef _MATERIAL_FEATURE_HAZY_GLOSS
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_HAZY_GLOSS;

    surfaceData.haziness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_HazinessMap), _HazinessMapChannelMask);
    surfaceData.haziness = lerp(_HazinessMapRange.x, _HazinessMapRange.y, surfaceData.haziness);
    surfaceData.haziness = lerp(_Haziness, surfaceData.haziness, _HazinessUseMap);

    surfaceData.hazeExtent = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_HazeExtentMap), _HazeExtentMapChannelMask);
    surfaceData.hazeExtent = lerp(_HazeExtentMapRange.x, _HazeExtentMapRange.y, surfaceData.hazeExtent);
    surfaceData.hazeExtent = lerp(_HazeExtent, surfaceData.hazeExtent, _HazeExtentUseMap);
    surfaceData.hazeExtent *= _HazeExtentMapRangeScale;
#ifndef _MATERIAL_FEATURE_SPECULAR_COLOR
    // base parametrization is baseColor + metallic, use value / option regarding how high can hazeExtent and f0 go:
    // If metallic parametrization is actually used, set the cap to be enforced later by the hazy gloss mapping,
    // it will be adjusted according to the metallic value such that
    // hazyGlossMaxf0 = ComputeFresnel0(1.0, surfaceData.metallic, surfaceData.hazyGlossMaxDielectricF0);
    surfaceData.hazyGlossMaxDielectricF0 = _HazyGlossMaxDielectricF0;
#else
    surfaceData.hazyGlossMaxDielectricF0 = 1.0;
#endif

#else // else not def _MATERIAL_FEATURE_HAZY_GLOSS
    surfaceData.lobeMix = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_LobeMixMap), _LobeMixMapChannelMask);
    surfaceData.lobeMix = lerp(_LobeMixMapRange.x, _LobeMixMapRange.y, surfaceData.lobeMix);
    surfaceData.lobeMix = lerp(_LobeMix, surfaceData.lobeMix, _LobeMixUseMap);

    surfaceData.perceptualSmoothnessB = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_SmoothnessBMap), _SmoothnessBMapChannelMask);
    surfaceData.perceptualSmoothnessB = lerp(_SmoothnessBMapRange.x, _SmoothnessBMapRange.y, surfaceData.perceptualSmoothnessB);
    surfaceData.perceptualSmoothnessB = lerp(_SmoothnessB, surfaceData.perceptualSmoothnessB, _SmoothnessBUseMap);
#endif // _MATERIAL_FEATURE_HAZY_GLOSS
#endif // _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE


    surfaceData.anisotropyA = 0.0;
    surfaceData.anisotropyB = 0.0;
#ifdef _MATERIAL_FEATURE_ANISOTROPY
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_ANISOTROPY;
    // TODO: manage anistropy map
    //surfaceData.anisotropy = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_AnistropyMap), _AnistropyMapChannelMask);
    //surfaceData.anisotropy = lerp(_AnistropyMapRange.x, _AnistropyMapRange.y, surfaceData.anisotropy);
    surfaceData.anisotropyA = _AnisotropyA; // In all cases we must multiply anisotropy with the map
#ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    surfaceData.anisotropyB = _AnisotropyB;
#endif
#endif // _MATERIAL_FEATURE_ANISOTROPY
    surfaceData.tangentWS = normalize(input.worldToTangent[0].xyz); // The tangent is not normalize in worldToTangent for mikkt. TODO: Check if it expected that we normalize with Morten. Tag: SURFACE_GRADIENT

    float4 coatGradient = float4(0.0, 0.0, 0.0, NORMALMAP_NEUTRAL_DISPERSION_VALUE);
#ifdef _MATERIAL_FEATURE_COAT
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_COAT;
    surfaceData.coatPerceptualSmoothness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_CoatSmoothnessMap), _CoatSmoothnessMapChannelMask);
    surfaceData.coatPerceptualSmoothness = lerp(_CoatSmoothnessMapRange.x, _CoatSmoothnessMapRange.y, surfaceData.coatPerceptualSmoothness);
    surfaceData.coatPerceptualSmoothness = lerp(_CoatSmoothness, surfaceData.coatPerceptualSmoothness, _CoatSmoothnessUseMap);
    surfaceData.coatIor = _CoatIor;
    surfaceData.coatThickness = _CoatThickness;
    surfaceData.coatExtinction = _CoatExtinction; // in thickness^-1 units

#ifdef _MATERIAL_FEATURE_COAT_NORMALMAP
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_COAT_NORMAL_MAP;
    if (_CoatNormalUseMap)
    {
        coatGradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_CoatNormalMap, _CoatNormalScale, _CoatNormalMapObjSpace);
    }
#endif

#else
    surfaceData.coatPerceptualSmoothness = 0.0;
    surfaceData.coatIor = 1.0001;
    surfaceData.coatThickness = 0.0;
    surfaceData.coatExtinction = float3(1.0, 1.0, 1.0);
#endif // _MATERIAL_FEATURE_COAT

#ifdef _MATERIAL_FEATURE_IRIDESCENCE
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_IRIDESCENCE;
    surfaceData.iridescenceIor = _IridescenceIor;
    surfaceData.iridescenceThickness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_IridescenceThicknessMap), _IridescenceThicknessMapChannelMask);
    surfaceData.iridescenceThickness = lerp(_IridescenceThicknessMapRange.x, _IridescenceThicknessMapRange.y, surfaceData.iridescenceThickness);
    surfaceData.iridescenceThickness = lerp(_IridescenceThickness, surfaceData.iridescenceThickness, _IridescenceThicknessUseMap);
    surfaceData.iridescenceMask = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_IridescenceMaskMap), _IridescenceMaskMapChannelMask);
    surfaceData.iridescenceMask = lerp(_IridescenceMaskMapRange.x, _IridescenceMaskMapRange.y, surfaceData.iridescenceMask);
    surfaceData.iridescenceMask = lerp(_IridescenceMask, surfaceData.iridescenceMask, _IridescenceMaskUseMap);

#else
    surfaceData.iridescenceIor = 1.0;
    surfaceData.iridescenceThickness = 0.0;
    surfaceData.iridescenceMask = 0.0;
#endif

#if defined(_MATERIAL_FEATURE_SUBSURFACE_SCATTERING) || defined(_MATERIAL_FEATURE_TRANSMISSION)
    surfaceData.diffusionProfile = _DiffusionProfile;
#else
    surfaceData.diffusionProfile = 0;
#endif

#ifdef _MATERIAL_FEATURE_SUBSURFACE_SCATTERING
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_SUBSURFACE_SCATTERING;
    surfaceData.subsurfaceMask = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_SubsurfaceMaskMap), _SubsurfaceMaskMapChannelMask);
    surfaceData.subsurfaceMask = lerp(_SubsurfaceMaskMapRange.x, _SubsurfaceMaskMapRange.y, surfaceData.subsurfaceMask);
    surfaceData.subsurfaceMask = lerp(_SubsurfaceMask, surfaceData.subsurfaceMask, _SubsurfaceMaskUseMap);
#else
    surfaceData.subsurfaceMask = 0.0;
#endif

#ifdef _MATERIAL_FEATURE_TRANSMISSION
    surfaceData.materialFeatures |= MATERIALFEATUREFLAGS_STACK_LIT_TRANSMISSION;
    surfaceData.thickness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_ThicknessMap), _ThicknessMapChannelMask);
    surfaceData.thickness = lerp(_ThicknessMapRange.x, _ThicknessMapRange.y, surfaceData.thickness);
    surfaceData.thickness = lerp(_Thickness, surfaceData.thickness, _ThicknessUseMap);
#else
    surfaceData.thickness = 1.0;
#endif

#ifdef _DETAILMAP
    float detailMask = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_DetailMaskMap), _DetailMaskMapChannelMask);

    float4 detailGradient = float4(0.0, 0.0, 0.0, NORMALMAP_NEUTRAL_DISPERSION_VALUE);
    if (_DetailNormalUseMap)
    {
        detailGradient = SAMPLE_TEXTURE2D_NORMAL_SCALE_BIAS(_DetailNormalMap, _DetailNormalScale, 0.0);
    }

    gradient = AddDetailGradient(gradient, detailGradient, detailMask);
    bentGradient = AddDetailGradient(bentGradient, detailGradient, detailMask);

    float detailPerceptualSmoothness = dot(SAMPLE_TEXTURE2D_SCALE_BIAS(_DetailSmoothnessMap), _DetailSmoothnessMapChannelMask);
    //debug: TODO either lineargrey or grey won't give 0.5 but 0.215 or 0.211
    //surfaceData.dielectricIor = detailPerceptualSmoothness;
    detailPerceptualSmoothness = lerp(_DetailSmoothnessMapRange.x, _DetailSmoothnessMapRange.y, detailPerceptualSmoothness);

    // We assume here that 0 <= _DetailSmoothnessMapRange.x < _DetailSmoothnessMapRange.y <= 1
    // (ie _DetailSmoothnessMapRemap should be (0,1) in the shader so the user can't set the remap endpoints outside this in the UI)
    // such that 0 <= detailPerceptualSmoothness <= 1 (numerical calculations implied by lerp might violate the later though)
    detailPerceptualSmoothness = detailPerceptualSmoothness * 2.0 - 1.0;
    /// remap [0,1] to [-1, 1] : positive values will push the final smoothness (absolutely) towards 1 and negative values toward 0.

    // Use overlay blend mode for detail:
    //
    // detailPerceptualSmoothness * _DetailSmoothnessScale from 0 to -1 controls a new absolute value for the smoothness
    // that is closer to the absolute 0.0 endpoint (it is linearly relative to the original smoothness and the slope of the
    // effect of the range of detailPerceptualSmoothness in [-1 to 0] is controlled by _DetailSmoothnessScale).
    // Likewise, for positive detailPerceptualSmoothness, the 0 to +1 range calculates a new value towards the 1.0 endpoint.
    //
    // So (detailPerceptualSmoothness distance from 0) * _DetailSmoothnessScale controls the new endpoint, and the detailMask
    // controls interpolation between the original smoothness value and the new endpoint calculated. Of course since both interpolations
    // are linear, the slope of the effect depends on both _DetailSmoothnessScale and detailMask, although because of saturation
    // in between, _DetailSmoothnessScale can be viewed as a thresholding control on the detail map before the application of
    // the mask interpolation.
    float smoothnessDetailSpeed = saturate(abs(detailPerceptualSmoothness) * _DetailSmoothnessScale);
    float smoothnessOverlay = lerp(surfaceData.perceptualSmoothnessA, (detailPerceptualSmoothness < 0.0) ? 0.0 : 1.0, smoothnessDetailSpeed);

    // Lerp with details mask
    surfaceData.perceptualSmoothnessA = lerp(surfaceData.perceptualSmoothnessA, saturate(smoothnessOverlay), detailMask);

    #ifdef _MATERIAL_FEATURE_DUAL_SPECULAR_LOBE
    // Note that this will be ignored when using Hazy Gloss parametrization.
    // This could be translated to apply to hazeExtent instead if we really want that control.

    smoothnessOverlay = lerp(surfaceData.perceptualSmoothnessB, (detailPerceptualSmoothness < 0.0) ? 0.0 : 1.0, smoothnessDetailSpeed);
    // Lerp with details mask
    surfaceData.perceptualSmoothnessB = lerp(surfaceData.perceptualSmoothnessB, saturate(smoothnessOverlay), detailMask);
    #endif
#endif
    // -------------------------------------------------------------
    // Surface Data Part 2 (outsite GetSurfaceData( ) in Lit shader):
    // -------------------------------------------------------------

    surfaceData.geomNormalWS = input.worldToTangent[2];
    // Convert back to world space normal
    surfaceData.normalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], gradient.xyz);
    surfaceData.bentNormalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], bentGradient.xyz);
    surfaceData.coatNormalWS = SurfaceGradientResolveNormal(input.worldToTangent[2], coatGradient.xyz);

    surfaceData.tangentWS = Orthonormalize(surfaceData.tangentWS, surfaceData.normalWS);

    if ((_GeometricNormalFilteringEnabled + _TextureNormalFilteringEnabled) > 0.0)
    {
        // TODO Note: specular occlusion that uses bent normals should also use filtering, although the visibility model is not a
        // specular lobe with roughness but a cone with solid angle determined by the ambient occlusion so this is an even more
        // empirical hack (with visibility modelled by a single circular region in direction space)
        // Intuitively, an increase of variance should enlarge (possible) visibility and thus diminish the occlusion
        // (enlarge the visibility cone). This goes in hand with the softer BSDF specular lobe.

        float geometricVariance = _GeometricNormalFilteringEnabled ? GeometricNormalVariance(input.worldToTangent[2], _SpecularAntiAliasingScreenSpaceVariance) : 0.0;
        float textureFilteringVariance = _TextureNormalFilteringEnabled ? DecodeNormalDispersionMeasureToVariance(gradient.w) : 0.0;
        float coatTextureFilteringVariance = _TextureNormalFilteringEnabled ? DecodeNormalDispersionMeasureToVariance(coatGradient.w) : 0.0;

        surfaceData.perceptualSmoothnessA = NormalFiltering(surfaceData.perceptualSmoothnessA, geometricVariance + textureFilteringVariance, _SpecularAntiAliasingThreshold);
        surfaceData.perceptualSmoothnessB = NormalFiltering(surfaceData.perceptualSmoothnessB, geometricVariance + textureFilteringVariance, _SpecularAntiAliasingThreshold);
        surfaceData.coatPerceptualSmoothness = NormalFiltering(surfaceData.coatPerceptualSmoothness, geometricVariance + coatTextureFilteringVariance, _SpecularAntiAliasingThreshold);
    }

    // TODO: decal etc.

#if defined(DEBUG_DISPLAY)
    if (_DebugMipMapMode != DEBUGMIPMAPMODE_NONE)
    {
        if (_BaseColorMapUV != TEXCOORD_INDEX_TRIPLANAR)
        {
            surfaceData.baseColor = GetTextureDataDebug(_DebugMipMapMode, uvMapping.texcoords[_BaseColorMapUV][_BaseColorMapUVLocal], _BaseColorMap, _BaseColorMap_TexelSize, _BaseColorMap_MipInfo, surfaceData.baseColor);
        }
        else
        {
            surfaceData.baseColor = float3(0.0, 0.0, 0.0);
        }
        surfaceData.metallic = 0.0;
    }
#endif

    // -------------------------------------------------------------
    // Builtin Data:
    // -------------------------------------------------------------

    // For back lighting we use the oposite vertex normal 
    InitBuiltinData(alpha, surfaceData.normalWS, -input.worldToTangent[2], input.positionRWS, input.texCoord1, input.texCoord2, builtinData);

    builtinData.emissiveColor = _EmissiveColor * lerp(float3(1.0, 1.0, 1.0), surfaceData.baseColor.rgb, _AlbedoAffectEmissive);
    builtinData.emissiveColor *= SAMPLE_TEXTURE2D_SCALE_BIAS(_EmissiveColorMap).rgb;

#if (SHADERPASS == SHADERPASS_DISTORTION) || defined(DEBUG_DISPLAY)
    float3 distortion = SAMPLE_TEXTURE2D(_DistortionVectorMap, sampler_DistortionVectorMap, input.texCoord0).rgb;
    distortion.rg = distortion.rg * _DistortionVectorScale.xx + _DistortionVectorBias.xx;
    builtinData.distortion = distortion.rg * _DistortionScale;
    builtinData.distortionBlur = clamp(distortion.b * _DistortionBlurScale, 0.0, 1.0) * (_DistortionBlurRemapMax - _DistortionBlurRemapMin) + _DistortionBlurRemapMin;
#endif

    PostInitBuiltinData(V, posInput, surfaceData, builtinData);
}
