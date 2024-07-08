/* 
/////////////////////////////////////////////////////////
//                ENBSeries effect file                //
//         visit http://enbdev.com for updates         //
//       Copyright (c) 2007-2018 Boris Vorontsov       //
//----------------------ENB PRESET---------------------//
			
					THE ENHANCER 1.1

//-----------------------CREDITS-----------------------//
// Boris: For ENBSeries and his knowledge and codes    //
// L00 :  Shader Setup, Presets and Settings,          //
//      Port, Modifications and author of this file    //
//     Please do not redistribute without credits      //
///////////////////////////////////////////////////////// 
*/

float		Empty00						<string UIName="THE ENHANCER v1.1";		string UIWidget="Spinner";float UIMin=0;float UIMax=0;> = {0.0};
//float		Empty01						<string UIName=" ";		string UIWidget="Spinner";float UIMin=0;float UIMax=0;> = {0.0};

//float 	ftest 		<string UIName="test"; string UIWidget="Spinner";  float UIMin=0.0;  float UIMax=10000000000.0;  float UIStep=0.1;> = {1.0};
//float 	ftest2 		<string UIName="test2"; string UIWidget="Spinner";  float UIMin=0.0;  float UIMax=10000000000.0;  float UIStep=0.1;> = {1.0};
//bool 	btest 		<string UIName="btest"; > = {true};
//bool 	btest2 		<string UIName="btest2"; > = {true};

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// EXTERNAL PARAMETERS BEGINS HERE, SHOULD NOT BE MODIFIED UNLESS YOU KNOW WHAT YOU ARE DOING
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

//x = generic timer in range 0..1, period of 16777216 ms (4.6 hours), y = average fps, w = frame time elapsed (in seconds)
float4	Timer;
//x = Width, y = 1/Width, z = aspect, w = 1/aspect, aspect is Width/Height
float4	ScreenSize;
//changes in range 0..1, 0 means full quality, 1 lowest dynamic quality (0.33, 0.66 are limits for quality levels)
float	AdaptiveQuality;
//x = current weather index, y = outgoing weather index, z = weather transition, w = time of the day in 24 standart hours. Weather index is value from weather ini file, for example WEATHER002 means index==2, but index==0 means that weather not captured.
float4	Weather;
//x = dawn, y = sunrise, z = day, w = sunset. Interpolators range from 0..1
float4	TimeOfDay1;
//x = dusk, y = night. Interpolators range from 0..1
float4	TimeOfDay2;
//changes in range 0..1, 0 means that night time, 1 - day time
float	ENightDayFactor;
//changes 0 or 1. 0 means that exterior, 1 - interior
float	EInteriorFactor;

// External ENB debugging paramaters
float4 tempF1;     /// 0,1,2,3  // Keyboard controlled temporary variables.
float4 tempF2;     /// 5,6,7,8  // Press and hold key 1,2,3...8 together with PageUp or PageDown to modify.
float4 tempF3;     /// 9,0
float4 tempInfo1;  /// xy = cursor position in range 0..1 of screen, z = is shader editor window active, w = mouse buttons with values 0..7

float4 Params01[7];  /// MOD PARAMATER, DO NOT MODIFY!
float4 ENBParams01;  /// x - bloom amount; y - lens amount

// TEXTURES
Texture2D TextureColor;       /// HDR color
Texture2D TextureBloom;       /// Fallout4 or ENB bloom
Texture2D TextureLens;        /// ENB lens fx
Texture2D TextureAdaptation;  /// Fallout4 or ENB adaptation
Texture2D TextureDepth;       /// Scene depth
Texture2D TextureAperture;    /// This frame aperture 1*1 R32F hdr red channel only. computed in depth of field shader file

// SAMPLERS
SamplerState Sampler0
{
  Filter=MIN_MAG_MIP_POINT;  AddressU=Clamp;  AddressV=Clamp;  /// MIN_MAG_MIP_LINEAR;
};
SamplerState Sampler1
{
  Filter=MIN_MAG_MIP_LINEAR;  AddressU=Clamp;  AddressV=Clamp;
};

// DATA STRUCTURE
struct VS_INPUT_POST
{
  float3 pos     : POSITION;
  float2 txcoord : TEXCOORD0;
};
struct VS_OUTPUT_POST
{
  float4 pos      : SV_POSITION;
  float2 txcoord0 : TEXCOORD0;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////
/// GAME IMAGE SPACES
static const float GameSaturation 	= 0.9 + Params01[3].x;
static const float gameBrightness 	= Params01[3].w;
static const float gameContrast 	= min(Params01[3].z,2.0f);
static const float3 tint_color 		= Params01[4].rgb; 
static const float tint_weight 		= saturate(Params01[4].w);
static const float3 fade        	= Params01[5].xyz; 
static const float fade_weight 		= min(Params01[5].w,0.1f);
static const float gameCurve  		= Params01[3].z;
static const float rBloomThreshold  = Params01[2].x;

#define remap(v, a, b) (((v) - (a)) / ((b) - (a)))
#define BIT_DEPTH 	10
#define LUM_709 	float3(0.2125, 0.7154, 0.0721) 
#define PixelSize 	float2(ScreenSize.y, ScreenSize.y * ScreenSize.z)

float linearDepth(float nonLinDepth, float depthNearVar, float depthFarVar)
	{
	  return (2.0 * depthNearVar) / (depthFarVar + depthNearVar - nonLinDepth * (depthFarVar - depthNearVar));
	}

float3 ChromaticAberration(float3 colorInput, float2 inTexCoords)
	{
		float3 color;

		color.r = TextureColor.Sample(Sampler0, inTexCoords + (PixelSize * 1.5)).r;
		color.g = colorInput.g;
		color.b = TextureColor.Sample(Sampler0, inTexCoords - (PixelSize * 1.5)).b;

		return lerp(colorInput, color, fade_weight*4.0);
	}

// TRI-DITHERING FUNCTION by SANDWICH-MAKER
float rand21(float2 uv)
	{
		float2 noise = frac(sin(dot(uv, float2(12.9898, 78.233) * 2.0)) * 43758.5453);
		return (noise.x + noise.y) * 0.5;
	}

float rand11(float x) { return frac(x * 0.024390243); }
float permute(float x) { return ((34.0 * x + 1.0) * x) % 289.0; }

float3 triDither(float3 color, float2 uv, float timer)
	{
		static const float bitstep = pow(2.0, BIT_DEPTH) - 1.0;
		static const float lsb = 1.0 / bitstep;
		static const float lobit = 0.5 / bitstep;
		static const float hibit = (bitstep - 0.5) / bitstep;

		float3 m = float3(uv, rand21(uv + timer)) + 1.0;
		float h = permute(permute(permute(m.x) + m.y) + m.z);

		float3 noise1, noise2;
		noise1.x = rand11(h); h = permute(h);
		noise2.x = rand11(h); h = permute(h);
		noise1.y = rand11(h); h = permute(h);
		noise2.y = rand11(h); h = permute(h);
		noise1.z = rand11(h); h = permute(h);
		noise2.z = rand11(h);

		float3 lo = saturate(remap(color.xyz, 0.0, lobit));
		float3 hi = saturate(remap(color.xyz, 1.0, hibit));
		float3 uni = noise1 - 0.5;
		float3 tri = noise1 - noise2;
		return float3(
			lerp(uni.x, tri.x, min(lo.x, hi.x)),
			lerp(uni.y, tri.y, min(lo.y, hi.y)),
			lerp(uni.z, tri.z, min(lo.z, hi.z))) * lsb;

	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////

// VERTEX SHADER

VS_OUTPUT_POST	VS_Draw(VS_INPUT_POST IN)
{
	VS_OUTPUT_POST	OUT;
	float4	pos;
	pos.xyz=IN.pos.xyz;
	pos.w=1.0;
	OUT.pos=pos;
	OUT.txcoord0.xy=IN.txcoord.xy;
	return OUT;
}

// PIXEL SHADER
//////////////////////////////////////////////////////////////////////////////
float4 PS_ENHANCER(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float4	color	= TextureColor.Sample(Sampler0, IN.txcoord0.xy);

/// ENB Adaptation
    float4	Adaptation=TextureAdaptation.Sample(Sampler0, IN.txcoord0.xy).x;
	float4 	middlegray=max(max(Adaptation.x, Adaptation.y), Adaptation.z);
	middlegray=max(middlegray, 0.0);
	middlegray=min(middlegray, 50.0);

/// ENB BLOOM
	float3	bloom	= TextureBloom.Sample(Sampler1, IN.txcoord0.xy);
	color.xyz+= max(0.0, bloom.xyz - color.xyz)*ENBParams01.x;

/// AGCC TINT
	color.a   = dot(color.xyz, LUM_709);
	color.xyz = lerp(color.xyz, tint_color * color.a, tint_weight);
	color.a = 1.0;
	
/// DEPTHS
	float Depth = TextureDepth.Sample(Sampler0, IN.txcoord0.xy ).x;
	float midDepth = linearDepth(Depth, 0.7f, 1000.0);
	float farDepth = linearDepth(Depth, 0.5f, 50000.0);
	
/// ENB LENS / Game bloom
	float3	lens=TextureLens.Sample(Sampler1, IN.txcoord0.xy).xyz;
	lens*= ENBParams01.y;
	color.xyz+= (lens.xyz * saturate(rBloomThreshold)) / (1 + color);

/// PP2
    color.xyz = color.xyz / (middlegray * 0.25 + 0.1); //AdaptMaxMin
	color.xyz *= 0.5*gameBrightness; //Brightness
    color.xyz += 0.000001;
    float3 xncol  = normalize(color.xyz);
    float3 scl    = color.xyz / xncol.xyz;
	scl = pow(scl, gameContrast); //Contrast
	
	float fSaturation = lerp((GameSaturation*0.9)+(tint_weight*0.33), GameSaturation*0.7, EInteriorFactor);
	xncol.xyz     = pow(xncol.xyz, lerp (fSaturation, fSaturation + (tint_weight*0.33), farDepth)); //Saturation
    color.xyz   = scl * xncol.xyz;
	
	// DEPTH BASED PP2 OVERSATURATION AND TONEMAPPING CURVES
	color.xyz   = (color.xyz * (1.0 + color.xyz / lerp(250.0, 200.0-(rBloomThreshold*100.0f), farDepth))) / 
	(color.xyz + lerp(lerp(0.7-(tint_weight*0.1)-(fade_weight*2.0), lerp(0.75f, 0.50f, midDepth)-(tint_weight*0.1)-(fade_weight*2.0), ENightDayFactor), 0.7-(tint_weight*0.1)-(fade_weight*2.0), EInteriorFactor));

/// DESATURATE SHADOW
	float tempgray=dot(color.xyz, 0.3333);
	float4	tempvar;
	
	tempvar.x=saturate(1.0-tempgray);
	tempvar.x*=tempvar.x;
	tempvar.x*=tempvar.x;
	color=lerp(color, tempgray, lerp(lerp(saturate(0.75f-tint_weight), lerp(0.75f, 0.2f, tint_weight),ENightDayFactor), 0.1f, EInteriorFactor) *tempvar.x);

/// AGCC FADE
	color.a   = dot(color.xyz, LUM_709);
	color.xyz = lerp(color.xyz, fade, fade_weight);
	color.a = 1.0;

/// FINAL	
	res.xyz = saturate(color);
	
/// DITHERING AND OUT	
	res.xyz += triDither(res.xyz, IN.txcoord0.xy, Timer.x);
	res.w=1.0;
	return res;
}


float4	PS_DepthSharp(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float4	color;
	float4	centercolor;
	
	float2	pixeloffset=ScreenSize.y;
	pixeloffset.y*=ScreenSize.z;

	float Depth = TextureDepth.Sample(Sampler0, IN.txcoord0.xy ).x;
	float closeDepth = linearDepth(Depth, 0.5f, 100.0);

	centercolor=TextureColor.Sample(Sampler0, IN.txcoord0.xy);
	color=0.0;
	float2	offsets[4]=
	{
		float2(-1.0,-1.0),
		float2(-1.0, 1.0),
		float2( 1.0,-1.0),
		float2( 1.0, 1.0),
	};
	for (int i=0; i<4; i++)
	{
		float2	coord=offsets[i].xy * pixeloffset.xy * (1.0f - closeDepth) + IN.txcoord0.xy;
		color.xyz+=TextureColor.Sample(Sampler1, coord.xy);
	}
	color.xyz *= 0.25;

	float	diffgray = dot((centercolor.xyz-color.xyz), 0.333);
	res.xyz = lerp(lerp(4.0,3.0,EInteriorFactor), 0.0f, closeDepth) * centercolor.xyz * diffgray + centercolor.xyz;
	
/// NIGHT EYE C.A
	res.rgb = ChromaticAberration(res.rgb,IN.txcoord0.xy);
	
	res.w=1.0;
	return res;
}


// VANILLA POST PROCESS, DO NOT MODIFY!
float4	PS_DrawOriginal(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float4	color;

	float2	scaleduv=Params01[6].xy*IN.txcoord0.xy;
	scaleduv=max(scaleduv, 0.0);
	scaleduv=min(scaleduv, Params01[6].zy);

	color=TextureColor.Sample(Sampler0, IN.txcoord0.xy); //hdr scene color

	float4	r0, r1, r2, r3;
	r1.xy=scaleduv;
	r0.xyz = color.xyz;
	if (0.5<=Params01[0].x) r1.xy=IN.txcoord0.xy;
	r1.xyz = TextureBloom.Sample(Sampler1, r1.xy).xyz;
	r2.xy = TextureAdaptation.Sample(Sampler1, IN.txcoord0.xy).xy; //in skyrimse it two component

	r0.w=dot(float3(2.125000e-001, 7.154000e-001, 7.210000e-002), r0.xyz);
	r0.w=max(r0.w, 1.000000e-005);
	r1.w=r2.y/r2.x;
	r2.y=r0.w * r1.w;
	if (0.5<Params01[2].z) r2.z=0xffffffff; else r2.z=0;
	r3.xy=r1.w * r0.w + float2(-4.000000e-003, 1.000000e+000);
	r1.w=max(r3.x, 0.0);
	r3.xz=r1.w * 6.2 + float2(5.000000e-001, 1.700000e+000);
	r2.w=r1.w * r3.x;
	r1.w=r1.w * r3.z + 6.000000e-002;
	r1.w=r2.w / r1.w;
	r1.w=pow(r1.w, 2.2);
	r1.w=r1.w * Params01[2].y;
	r2.w=r2.y * Params01[2].y + 1.0;
	r2.y=r2.w * r2.y;
	r2.y=r2.y / r3.y;
	if (r2.z==0) r1.w=r2.y; else r1.w=r1.w;
	r0.w=r1.w / r0.w;
	r1.w=saturate(Params01[2].x - r1.w);
	r1.xyz=r1 * r1.w;
	r0.xyz=r0 * r0.w + r1;
	r1.x=dot(r0.xyz, float3(2.125000e-001, 7.154000e-001, 7.210000e-002));
	r0.w=1.0;
	r0=r0 - r1.x;
	r0=Params01[3].x * r0 + r1.x;
	r1=Params01[4] * r1.x - r0;
	r0=Params01[4].w * r1 + r0;
	r0=Params01[3].w * r0 - r2.x;
	r0=Params01[3].z * r0 + r2.x;
	r0.xyz=saturate(r0);
	r1.xyz=pow(r1.xyz, Params01[6].w);
	//active only in certain modes, like khajiit vision, otherwise Params01[5].w=0
	r1=Params01[5] - r0;
	res=Params01[5].w * r1 + r0;

	return res;
}

///TECHNIQUES

technique11 ENHANCER <string UIName="THE ENHANCER";>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Draw()));
		SetPixelShader(CompileShader(ps_5_0, PS_ENHANCER()));
	}
}

technique11 ENHANCER1
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Draw()));
		SetPixelShader(CompileShader(ps_5_0, PS_DepthSharp()));
	}
}
