/* /////////////////////////////////////////////////////////
//                ENBSeries effect file                //
//         visit http://enbdev.com for updates         //
//       Copyright (c) 2007-2015 Boris Vorontsov       //
//----------------------ENB PRESET---------------------//
					THE ENHANCER 1.0 
//-----------------------CREDITS-----------------------//
//     Please do not redistribute without credits      //
// Boris: For ENBSeries and his knowledge and codes    //
// Matso: Author of original DOF code          	   	   //
// L00 :  Shader Setup, Presets and Settings,          //
//        Port and Modification of Shaders             //
//        and author of this file                      //
/////////////////////////////////////////////////////////
//                		THE ENHANCER                   //
//-----------------------------------------------------// */

//+++++++++++++++++++++++++++++
// Internal parameters, can be modified
//+++++++++++++++++++++++++++++
bool	bManualFocus			<string UIName="Manual Focus (Click on Focus Point)";> = {false};
int		iDOFPreset				<string UIName="Blur Power";string UIWidget="quality";int UIMin=-1;int UIMax=4;> = {1};

#define fFocusBias 		0.045
#define fBlurScale		fBS*0.0035
#define fBokehIntensity	fBI*0.9
#define fADOF_AutofocusCenter 		float2(0.43,0.43)
//+++++++++++++++++++++++++++++
//external enb parameters, do not modify
//+++++++++++++++++++++++++++++
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


//+++++++++++++++++++++++++++++
//external enb debugging parameters for shader programmers, do not modify
//+++++++++++++++++++++++++++++
//keyboard controlled temporary variables. Press and hold key 1,2,3...8 together with PageUp or PageDown to modify. By default all set to 1.0
float4	tempF1; //0,1,2,3
float4	tempF2; //5,6,7,8
float4	tempF3; //9,0
// xy = cursor position in range 0..1 of screen;
// z = is shader editor window active;
// w = mouse buttons with values 0..7 as follows:
//    0 = none
//    1 = left
//    2 = right
//    3 = left+right
//    4 = middle
//    5 = left+middle
//    6 = right+middle
//    7 = left+right+middle (or rather cat is sitting on your mouse)
float4	tempInfo1;
// xy = cursor position of previous left mouse button click
// zw = cursor position of previous right mouse button click
float4	tempInfo2;

//+++++++++++++++++++++++++++++
//mod parameters, do not modify
//+++++++++++++++++++++++++++++
//z = ApertureTime multiplied by time elapsed, w = FocusingTime multiplied by time elapsed
float4				DofParameters;

Texture2D			TextureCurrent; //current frame focus depth or aperture. unused in dof computation
Texture2D			TexturePrevious; //previous frame focus depth or aperture. unused in dof computation

Texture2D			TextureOriginal; //color R16B16G16A16 64 bit hdr format
Texture2D			TextureColor; //color which is output of previous technique (except when drawed to temporary render target), R16B16G16A16 64 bit hdr format
Texture2D			TextureDepth; //scene depth R32F 32 bit hdr format
Texture2D			TextureFocus; //this frame focus 1*1 R32F hdr red channel only. computed in PS_Focus
Texture2D			TextureAperture; //this frame aperture 1*1 R32F hdr red channel only. computed in PS_Aperture
Texture2D			TextureAdaptation; //previous frame vanilla or enb adaptation 1*1 R32F hdr red channel only. adaptation computed after depth of field and it's kinda "average" brightness of screen!!!
Texture2D 			texNoise;

//temporary textures which can be set as render target for techniques via annotations like <string RenderTarget="RenderTargetRGBA32";>
Texture2D			RenderTargetRGBA32; //R8G8B8A8 32 bit ldr format
Texture2D			RenderTargetRGBA64; //R16B16G16A16 64 bit ldr format
Texture2D			RenderTargetRGBA64F; //R16B16G16A16F 64 bit hdr format
Texture2D			RenderTargetR16F; //R16F 16 bit hdr format with red channel only
Texture2D			RenderTargetR32F; //R32F 32 bit hdr format with red channel only
Texture2D			RenderTargetRGB32F; //32 bit hdr format without alpha

SamplerState		Sampler0
{
	Filter = MIN_MAG_MIP_POINT;//MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

SamplerState		Sampler1
{
	Filter = MIN_MAG_MIP_LINEAR;
	AddressU = Clamp;
	AddressV = Clamp;
};

SamplerState		SamplerFocus
{
	Filter = MIN_MAG_MIP_Linear;
	AddressU = Clamp;
	AddressV = Clamp;
};

// Useful constants
#define PI				3.1415926535897932384626433832795
#define CHROMA_POW		32.0								// the bigger the value, the more visible chomatic aberration effect in DoF

// DoF constants
#define DOF_SCALE		2356.1944901923449288469825374596	// PI * 750
// Set those below for diffrent blur shapes
#define FIRST_PASS		0	// only 0, 1, 2, or 3
#define SECOND_PASS		1	// only 0, 1, 2, or 3
#define THIRD_PASS		2	// only 0, 1, 2, or 3
#define FOURTH_PASS		3	// only 0, 1, 2, or 3


#ifdef bManualFocus
	#define DOF(sd,sf)		fBlurScale * smoothstep(fDofBias * tempF1.y, fDofCutoff * tempF1.z, abs(sd - sf))
#else
	#define DOF(sd,sf)		fBlurScale * smoothstep(fDofBias, fDofCutoff, abs(sd - sf))
#endif


#define BOKEH_DOWNBLUR	0.3		// the default blur scale is too big for bokeh
	
#define EFocusingSensitivity 0.5
#define EApertureSize 1.0
#define ESensorSize 25.0
#define EBokehSoftness 0.1
#define EBlurRange 2.0

// Methods enabling options

#define USE_SMOOTH_DOF	1			// comment it to disable smooth DoF
#define USE_BOKEH_DOF	1			// comment it to disable bokeh DoF
#define USE_NATURAL_BOKEH	1			// diffrent, more natural bokeh shape (comment to disable)
#define USE_ENHANCED_BOKEH	1			// more pronounced bokeh blur (comment to disable)

// Chromatic aberration parameters
float3 fvChroma = float3(0.9995, 1.000, 1.0005);// displacement scales of red, green and blue respectively
#define fBaseRadius 0.9							// below this radius the effect is less visible
#define fFalloffRadius 1.8						// over this radius the effect is max

// Sharpen parameters
float2 fvTexelSize = float2(1.0 / 1920.0, 1.0 / 1080.0);	// set your resolution sizes

// Depth of field parameters
//#define fFocusBias 0.045						// 0.045 bigger values for nearsightedness, smaller for farsightedness (lens focal point distance)
#define fDofCutoff 0.2							// 0.25 manages the smoothness of the DoF (bigger value results in wider depth of field)
#define fDofBias 0.07							// distance not taken into account in DoF (all closer then the distance is in focus)
//#define fBlurScale 0.0034						// .0038 governs image blur scale (the bigger value, the stronger blur)
#define fBlurCutoff 0.05					    //0.15 bluring tolerance depending on the pixel and sample depth (smaller causes objects edges to be preserved)

#ifdef bManualFocus
	#define fCloseDofDistance 0.05
#else
	#define fCloseDofDistance 0.28
#endif


#define fStepScale 0.00015

// Bokeh parameters
#define fBokehCurve 4.0							// the larger the value, the more visible the bokeh effect is (not used with brightness limiting)
//#define fBokehIntensity 0.95					// governs bokeh brightness (not used with brightness limiting)
#define fBokehConstant 0.1						// constant value of the bokeh weighting
#define fBokehMaxLevel 45.0						// bokeh max brightness level (scale factor for bokeh samples)
#define fBokehMin 0.001							// min input cutoff (anything below is 0)
#define fBokehMax 1.925							// max input cutoff (anything above is 1)
#define fBokehMaxWeight 25.0					// any weight above will be clamped

#define fBokehLuminance	0.956					// bright pass of the bokeh weight used with radiant version of the bokeh
#define BOKEH_RADIANT	float3 bct = ct.rgb;float b = GrayScale(bct) + fBokehConstant + length(bct)
#define BOKEH_PASTEL	float3 bct = BrightBokeh(ct.rgb);float b = dot(bct, bct) + fBokehConstant
#define BOKEH_VIBRANT	float3 bct = BrightBokeh(ct.rgb);float b = GrayScale(ct.rgb) + dot(bct, bct) + fBokehConstant
#define BOKEH_FORMULA	BOKEH_RADIANT           // choose one of the above
#define FAR_CLIP_DIST	10000000.0								
#define NEAR_CLIP_DIST	10.0									
#define DEPTH_RANGE		-(NEAR_CLIP_DIST-FAR_CLIP_DIST)*0.01	
#define linear(t)		((2.0 * NEAR_CLIP_DIST) / (NEAR_CLIP_DIST + FAR_CLIP_DIST - t * (FAR_CLIP_DIST - NEAR_CLIP_DIST)))

// Anamorphic flare parameters
#define fFlareLuminance 2.0						// bright pass luminance value 
#define fFlareBlur 500.0						// manages the size of the flare
#define fFlareIntensity 0.05					// effect intensity

// Bokeh shape offset weights
#define DEFAULT_OFFSETS	{ -1.282, -0.524, 0.524, 1.282 }

// Sampling vectors	
float offset[4] = DEFAULT_OFFSETS;

float2 tds[16] = { 
	float2(0.2007, 0.9796),
	float2(-0.2007, 0.9796), 
	float2(0.2007, 0.9796),
	float2(-0.2007, 0.9796), 
		
	float2(0.8240, 0.5665),
	float2(0.5665, 0.8240),
	float2(0.8240, 0.5665),
	float2(0.5665, 0.8240),

	float2(0.9796, 0.2007),
	float2(0.9796, -0.2007),
	float2(0.9796, 0.2007),
	float2(0.9796, -0.2007),
		
	float2(-0.8240, 0.5665),
	float2(-0.5665, 0.8240),
	float2(-0.8240, 0.5665),
	float2(-0.5665, 0.8240)
};			// Natural bokeh sampling directions

float2 rnds[16] = {
	float2(0.326212, 0.40581),
    float2(0.840144, 0.07358),
    float2(0.695914, 0.457137),
    float2(0.203345, 0.620716),
    float2(0.96234, 0.194983),
    float2(0.473434, 0.480026),
    float2(0.519456, 0.767022),
    float2(0.185461, 0.893124),
    float2(0.507431, 0.064425),
    float2(0.89642, 0.412458),
    float2(0.32194, 0.932615),
    float2(0.791559, 0.59771),
	float2(0.979602, 0.10275),
	float2(0.56653, 0.82401),
	float2(0.20071, 0.97966),
	float2(0.98719, 0.12231)
};
//+++++++++++++++++++++++++++++
//
//+++++++++++++++++++++++++++++
struct VS_INPUT_POST
{
	float3 pos		: POSITION;
	float2 txcoord	: TEXCOORD0;
};
struct VS_OUTPUT_POST
{
	float4 pos		: SV_POSITION;
	float2 txcoord0	: TEXCOORD0;
};



//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
VS_OUTPUT_POST	VS_Quad(VS_INPUT_POST IN)
{
	VS_OUTPUT_POST	OUT;
	float4	pos;
	pos.xyz=IN.pos.xyz;
	pos.w=1.0;
	OUT.pos=pos;
	OUT.txcoord0.xy=IN.txcoord.xy;
	return OUT;
}

////////////////////////////////////////////////////////////////////
//first passes to compute focus distance and aperture, temporary
//render targets are not available for them
////////////////////////////////////////////////////////////////////
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//output size is 1*1
//TexturePrevious size is 1*1
//TextureCurrent not exist, so set to white 1.0
//output and input textures are R32 float format (red channel only)
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
float4	PS_Aperture(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float	curr;
	float	prev=TexturePrevious.Sample(Sampler0, IN.txcoord0.xy).x;

	curr=EApertureSize; 
	curr=max(curr, 1.0); 
	curr=1.0/curr; 

	res=lerp(prev, curr, DofParameters.z); 

	res=max(res, 0.0000000001);
	res=min(res, 1.0);

	res.w=1.0;
	return res;
}



//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//output size is 16*16
//output texture is R32 float format (red channel only)
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
float4	PS_ReadFocus(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float2	pos;
	float2	coord;
	float	curr=0.0;
	float tempcurr=0.0;
	const float	step=1.0/16.0;
	const float	halfstep=0.5/16.0;
	pos.x=halfstep;
	for (int x=0; x<16; x++)
	{
		pos.y=halfstep;
		for (int y=0; y<16; y++)
		{
			if (bManualFocus == true)								
			{
				coord = tempInfo2.xy;
					
			} 
			else
			{
				coord=pos.xy * 0.05;
				coord+=IN.txcoord0.xy * 0.05 + float2(fADOF_AutofocusCenter);
			}	
			tempcurr=TextureDepth.SampleLevel(Sampler0, coord, 0.0).x;	
			
			//do not blur first person models like weapons and hands
			const float	fpdistance=1.0/0.085;
			float	fpfactor=1.0-saturate(1.0 - tempcurr * fpdistance);
			tempcurr=lerp(1.0, tempcurr, fpfactor*fpfactor);
			curr+=tempcurr;

			pos.y+=step;
		}
		pos.x+=step;
	}
	curr*=1.0/(16.0*16.0);
	res=curr;

	res=max(res, 0.0);
	res=min(res, 1.0);

	return res;
}



//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//output size is 1*1
//TexturePrevious size is 1*1
//TextureCurrent size is 16*16
//output and input textures are R32 float format (red channel only)
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
float4	PS_Focus(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;
	float	prev=TexturePrevious.Sample(Sampler0, IN.txcoord0.xy).x;
	float2	pos;
	float	curr=0.0;
	float	currmin=1.0;
	const float	step=1.0/16.0;
	const float	halfstep=0.5/16.0;
	pos.x=halfstep;
	for (int x=0; x<16; x++)
	{
		pos.y=halfstep;
		for (int y=0; y<16; y++)
		{
			float	tempcurr=TextureCurrent.Sample(Sampler0, IN.txcoord0.xy + pos.xy).x;
			currmin=min(currmin, tempcurr);
			curr+=tempcurr;

			pos.y+=step;
		}
		pos.x+=step;
	}
	curr*=1.0/(16.0*16.0);
	curr=lerp(curr, currmin, EFocusingSensitivity);

	res=lerp(prev, curr, DofParameters.w); 
	res=max(res, 0.0);
	res=min(res, 1.0);

	res.w=1.0;
	return res;
}


float4 ChromaticAberration(float2 tex, float outOfFocus)
{
	int fChromaPower;
	if  (bManualFocus) fChromaPower=8;
	else fChromaPower=0;

	float d = distance(tex, float2(0.5, 0.5));
	float f = smoothstep(fBaseRadius, fFalloffRadius, d);
	float3 chroma = pow(f + fvChroma, CHROMA_POW * outOfFocus * fChromaPower);

	float2 tr = ((2.0 * tex - 1.0) * chroma.r) * 0.5 + 0.5;
	float2 tg = ((2.0 * tex - 1.0) * chroma.g) * 0.5 + 0.5;
	float2 tb = ((2.0 * tex - 1.0) * chroma.b) * 0.5 + 0.5;
	
	float3 color = float3(TextureColor.Sample(Sampler0, tr).r, TextureColor.Sample(Sampler0, tg).g, TextureColor.Sample(Sampler0, tb).b) * (1.0 - outOfFocus);
	
	return float4(color, 1.0);
}


float3 BrightPass(float2 tex)
{
	float3 c = TextureColor.Sample(Sampler0, tex).rgb;
    float3 bC = max(c - float3(fFlareLuminance, fFlareLuminance, fFlareLuminance), 0.0);
    float bright = dot(bC, 1.0);
    bright = smoothstep(0.0f, 0.5, bright);
    return lerp(0.0, c, bright);
}

float3 BrightColor(float3 c)
{
    float3 bC = max(c - float3(fFlareLuminance, fFlareLuminance, fFlareLuminance), 0.0);
    float bright = dot(bC, 1.0);
    bright = smoothstep(0.0f, 0.5, bright);
    return lerp(0.0, c, bright);
}

float3 BrightBokeh(float3 c)
{
    float3 bC = max(c - float3(fBokehLuminance, fBokehLuminance, fBokehLuminance), 0.0);
    float bright = dot(bC, 1.0);
    bright = smoothstep(0.0f, 0.5, bright);
    return lerp(0.0, c, bright);
}

float3 AnamorphicSample(int axis, float2 tex, float blur)
{
	tex = 2.0 * tex - 1.0;
	if (!axis) tex.x /= -blur;
	else tex.y /= -blur;
	tex = 0.5 * tex + 0.5;
	return BrightPass(tex);
}

float GrayScale(float3 sample)
{
	return dot(sample, float3(0.3, 0.59, 0.11));
}


///// PIXEL SHADERS ////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////
//multiple passes for computing depth of field, with temporary render
//targets support.
//TextureCurrent, TexturePrevious are unused
////////////////////////////////////////////////////////////////////
//draw to temporary render target
float4	PS_ComputeFactor(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;

	float	depth=TextureDepth.Sample(Sampler0, IN.txcoord0.xy).x;
	float	focus=TextureFocus.Sample(Sampler0, IN.txcoord0.xy).x;
	float	aperture=TextureAperture.Sample(Sampler0, IN.txcoord0.xy).x;
	
	//clamp to avoid potenrial bugs
	depth=max(depth, 0.0);
	depth=min(depth, 1.0);

	//compute blur radius
	float	scaling=EBlurRange; //abstract scale in screen space
	float	factor=depth-focus;

	factor=factor * ESensorSize * aperture * scaling;
	//limit size
	float	screensizelimit=ESensorSize * scaling;
	factor=max(factor, -screensizelimit);
	factor=min(factor, screensizelimit);

	res=factor;

	//do not blur first person models like weapons
	const float	fpdistance=1.0/0.085;
	float	fpfactor=1.0-saturate(1.0 - depth * fpdistance);
	res=res * fpfactor*fpfactor;

	return res;
}


// Anamorphic lens flare pixel shader (Matso code)
float4 PS_ProcessPass_Anamorphic(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
float4 res;
	float2 coord = IN.txcoord0.xy;
	float3 anamFlare = AnamorphicSample(0, coord.xy, fFlareBlur) * float3(0.0, 0.0, 1.0);
	
	res.rgb = anamFlare * fFlareIntensity;
	res.a = 1.0;

	res.rgb += TextureColor.Sample(Sampler0, coord.xy).rgb;

	return res;
}


// Depth of field pixel shader (Matso code)
float4 PS_ProcessPass_DepthOfField(VS_OUTPUT_POST IN, float4 v0 : SV_Position0, uniform int axis) : SV_Target
{
float4 res;
	float2 base = IN.txcoord0.xy;
	float4 tcol = TextureColor.Sample(Sampler0, base.xy);
	float sd =TextureDepth.Sample(Sampler0, base.xy).x;						// acquire scene depth for the pixel
	res = tcol;

	float depth = linear(TextureDepth.Sample(Sampler1, base).x);
	float z = depth * DEPTH_RANGE;
	
	float	fBS;
	float	fBI;
	
	if (iDOFPreset==2) {
	fBS 	=	0.45;
	fBI 	=	0.25;
	}
	if (iDOFPreset==1) {
	fBS 	=	0.8;
	fBI 	=	0.5;
	}
	if (iDOFPreset==0) {
	fBS 	=	1.0f;
	fBI 	=	0.75;
	}
	if (iDOFPreset==-1) {
	fBS 	=	1.5;
	fBI 	=	1.0f;
	}
	
#ifndef USE_SMOOTH_DOF										// sample focus value
	float sf = TextureDepth.Sample(Sampler0, 0.5).x - fFocusBias;
#else
	float sf = TextureFocus.Sample(Sampler0, 0.5).x - fFocusBias * 2.0;
#endif
	float outOfFocus = DOF(sd, sf);
	
	if (bManualFocus == false)								
	{
		outOfFocus*= smoothstep(fCloseDofDistance - 0.05, fCloseDofDistance, z);
	}
	float blur = DOF_SCALE * outOfFocus;
	float wValue = 1.0;


#ifndef USE_CLOSE_DOF_ONLY
 #ifdef USE_BOKEH_DOF
	blur *= BOKEH_DOWNBLUR;									// should bokeh be used, decrease blur a bit
 #endif
#else	
	blur *= (smoothstep(fCloseDofDistance, 0.0, sf) * 2.0);
	if (blur > 0.001)
#endif

	for (int i = 0; i < 4; i++)
	{
#ifndef USE_NATURAL_BOKEH
		float2 tdir = tds[axis] * fvTexelSize * blur * offset[i];
#else
		float2 tdir = tds[axis * 4 + i] * fvTexelSize * blur * offset[i];
#endif
		
		float2 coord = base + tdir.xy;

		float4 ct = ChromaticAberration(coord, outOfFocus);			// chromatic aberration sampling

		float sds = TextureDepth.Sample(Sampler0, coord).x;
		
		if ((abs(sds - sd) / sd) <= fBlurCutoff) {							// blur 'bleeding' control
#ifndef USE_BOKEH_DOF
			float w = 1.0 + abs(offset[i]);							// weight blur for better effect
#else		
  #if USE_BOKEH_DOF == 1
  			BOKEH_FORMULA;
    #ifndef USE_BRIGHTNESS_LIMITING									// all samples above max input will be limited to max level
			float w = pow(b * fBokehIntensity, fBokehCurve);
    #else
	 #ifdef USE_ENHANCED_BOKEH
			float w = smoothstep(fBokehMin, fBokehMax, b * b) * fBokehMaxLevel;
	 #else
	 		float w = smoothstep(fBokehMin, fBokehMax, b) * fBokehMaxLevel;
	 #endif
    #endif
	#ifdef USE_WEIGHT_CLAMP
			w = min(w, fBokehMaxWeight);
	#endif
			w += abs(offset[i]) + blur;
  #endif
  
#endif	
			tcol += ct * w;
			wValue += w;
		}
	}

	tcol /= wValue;
	
	
	res.rgb = tcol.rgb;
	res.w = 1.0;
	return res;
}


//example of blur. without any fixes of artifacts and low performance
float4	PS_Dof(VS_OUTPUT_POST IN, float4 v0 : SV_Position0) : SV_Target
{
	float4	res;

	float	focusing;
	focusing=RenderTargetR16F.Sample(Sampler0, IN.txcoord0.xy).x;

	float2	sourcesizeinv;
	float2	fstepcount;
	sourcesizeinv=ScreenSize.y;
	sourcesizeinv.y=ScreenSize.y*ScreenSize.z;
	fstepcount.x=ScreenSize.x;
	fstepcount.y=ScreenSize.x*ScreenSize.w;

	float2	pos;
	float2	coord;
	float4	curr=0.0;
	float	weight=0.000001;

	fstepcount=abs(focusing);
	sourcesizeinv*=focusing;

	fstepcount=min(fstepcount, 32.0);
	fstepcount=max(fstepcount, 0.0);

	int	stepcountX=(int)(fstepcount.x+1.4999);
	int	stepcountY=(int)(fstepcount.y+1.4999);
	fstepcount=max(fstepcount, 2.0);
	float2	halfstepcountinv=2.0/fstepcount;
	pos.x=-1.0+halfstepcountinv.x;
	for (int x=0; x<stepcountX; x++)
	{
		pos.y=-1.0+halfstepcountinv.y;
		for (int y=0; y<stepcountY; y++)
		{
			float	tempweight;
			float	rangefactor=dot(pos.xy, pos.xy);
			coord=pos.xy * sourcesizeinv;
			coord+=IN.txcoord0.xy;
			float4	tempcurr=TextureColor.SampleLevel(Sampler1, coord.xy, 0.0);
			tempweight=saturate(1001.0 - 1000.0*rangefactor);//arithmetic version to cut circle from square
			tempweight*=saturate(1.0 - rangefactor * EBokehSoftness);
			curr.xyz+=tempcurr.xyz * tempweight;
			weight+=tempweight;

			pos.y+=halfstepcountinv.y;
		}
		pos.x+=halfstepcountinv.x;
	}
	curr.xyz/=weight;

	res.xyz=curr;

	res.w=1.0;
	return res;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//write aperture with time factor, this is always first technique
technique11 Aperture
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_Aperture()));
	}
}

//compute focus from depth of screen and may be brightness, this is always second technique
technique11 ReadFocus
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ReadFocus()));
	}
}

//write focus with time factor, this is always third technique
technique11 Focus
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_Focus()));
	}
}
////////////////////////////////////////////////////////////////////
// End focusing code
////////////////////////////////////////////////////////////////////

technique11 Dof <string UIName="THE ENHANCER"; string RenderTarget="RenderTargetR16F";>
{
	pass p0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ComputeFactor()));
	}
}

technique11 Dof1
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ProcessPass_DepthOfField(FIRST_PASS)));
	}
}

technique11 Dof2
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ProcessPass_DepthOfField(SECOND_PASS)));
	}
}
technique11 Dof3
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ProcessPass_DepthOfField(THIRD_PASS)));
	}
}

technique11 Dof4
{
	pass P0
	{
		SetVertexShader(CompileShader(vs_5_0, VS_Quad()));
		SetPixelShader(CompileShader(ps_5_0, PS_ProcessPass_DepthOfField(FOURTH_PASS)));
	}
}
