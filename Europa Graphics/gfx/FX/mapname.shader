## Includes

Includes = {
	"constants.fxh"
	"standardfuncsgfx.fxh"
}


## Samplers

PixelShader = 
{
	Samplers = 
	{
		DiffuseTexture = 
		{
			AddressV = "Clamp"
			MagFilter = "Linear"
			MipMapLodBias = 0
			AddressU = "Clamp"
			Index = 0
			MipFilter = "Linear"
			MinFilter = "Linear"
		}

		FoWTexture = 
		{
			AddressV = "Wrap"
			MagFilter = "Linear"
			AddressU = "Wrap"
			Index = 1
			MipFilter = "Linear"
			MinFilter = "Linear"
		}

		FoWDiffuse = 
		{
			AddressV = "Wrap"
			MagFilter = "Linear"
			AddressU = "Wrap"
			Index = 2
			MipFilter = "Linear"
			MinFilter = "Linear"
		}


	}
}


## Vertex Structs


VertexStruct VS_INPUT
{
    float3 vPosition  : POSITION;
	float2 vTexCoord  : TEXCOORD0;
};


VertexStruct VS_OUTPUT
{
    float4 vPosition : PDX_POSITION;
	float3 vPrepos   : TEXCOORD0;
    float2 vTexCoord : TEXCOORD1;
};


## Constant Buffers

ConstantBuffer( 1, 32 )
{
	float2 vTargetOpacity_Fade;
}

## Shared Code

Code
[[
#ifndef THANATOS

/* COLOURS:
RGBA format, alpha must be below 1.000, cannot be 1.000.*/
static const float4 INTERIOR_COLOUR			= float4(0.000f, 0.000f, 0.000f, 0.751f); // Transparent black
static const float4 L_OUTLINE_COLOUR		= float4(0.000f, 0.000f, 0.000f, 0.999f); // Solid black
static const float4 L_GLOW_COLOUR			= float4(0.300f, 0.300f, 0.300f, 0.240f); // Transparent grey

/* MIPMAPS
The higher this is, the more text that is defined as small text, anything > 10 will include all text.*/
static const float MIPPYMAPPY	= 5.5;

/*THRESHOLDS
Defines how thick each section is, 1=centre, 0=edge.*/
static const float INTERIOR		= 0.5; 

static const float L_OUTLINE	= 0.5; 
static const float L_GLOW		= 0.4; 

//God knows what this does but it works, don't @ me.
float filterwidth(float2 v)
{
	#ifdef PDX_OPENGL
		#ifdef PIXEL_SHADER
			return (abs(fwidth(v.x)) + abs(fwidth(v.y))) / 2.0f;
		#else
			return 0.002f;
		#endif //PIXEL_SHADER
	#else
		float2 fw = max(abs(ddx(v)), abs(ddy(v)));
		return (fw.x + fw.y) / 2.0f;// return max(fw.x, fw.y);
	#endif //PDX_OPENGL
}
//YEAH, SCIENCE B***H! (Idk how this works)
float mip_map_level(in float2 texture_coordinate) // Finds mip map level, see https://forum.unity.com/threads/calculate-used-mipmap-level-ddx-ddy.255237/
{
  float2  dx_vtc  = ddx(texture_coordinate);		
  float2  dy_vtc  = ddy(texture_coordinate);
  float delta_max_sqr = max(dot(dx_vtc, dx_vtc), dot(dy_vtc, dy_vtc));
  return 0.5 * log2(delta_max_sqr);
}
#endif
]]

## Vertex Shaders

VertexShader = 
{
	MainCode VertexShader
	[[
		VS_OUTPUT main( const VS_INPUT v )
		{
			VS_OUTPUT Out;
			float4 vPos = float4( v.vPosition, 1.0f );
			float4 vDistortedPos = vPos - float4( vCamLookAtDir * 0.5f, 0.0f );
			vPos = mul( ViewProjectionMatrix, vPos );
			
			// move z value slightly closer to camera to avoid intersections with terrain
			float vNewZ = dot( vDistortedPos, float4( GetMatrixData( ViewProjectionMatrix, 2, 0 ), GetMatrixData( ViewProjectionMatrix, 2, 1 ), GetMatrixData( ViewProjectionMatrix, 2, 2 ), GetMatrixData( ViewProjectionMatrix, 2, 3 ) ) );
			
			Out.vPosition = float4( vPos.xy, vNewZ, vPos.w );
			Out.vPrepos = v.vPosition.xyz;
			Out.vTexCoord = v.vTexCoord;
			return Out;
		}
	]]

}


## Pixel Shaders

PixelShader = 
{
	MainCode PixelShader
	[[
		float4 main( VS_OUTPUT v ) : PDX_COLOR
		{
			float vDistance = 0.0f;
			if (v.vTexCoord.y > 3.0f) {
				vDistance = tex2D( DiffuseTexture, float2(v.vTexCoord.x, v.vTexCoord.y - 3.0f) ).a;
			}
			else if (v.vTexCoord.y > 2.0f) {
				vDistance = tex2D( DiffuseTexture, float2(v.vTexCoord.x, v.vTexCoord.y - 2.0f) ).b;
			}
			else if (v.vTexCoord.y > 1.0f) {
				vDistance = tex2D( DiffuseTexture, float2(v.vTexCoord.x, v.vTexCoord.y - 1.0f) ).g;
			}
			else {
				vDistance = tex2D( DiffuseTexture, float2(v.vTexCoord.x, v.vTexCoord.y) ).r;
			}
			//Core (Don't touch)
			float smoothing = filterwidth(v.vTexCoord) * 50.0f;
			float lod = -mip_map_level(v.vTexCoord);
			float is_tiny = 1.0f - saturate(lod - MIPPYMAPPY);

			float4 vMapname = lerp(INTERIOR_COLOUR, 0, 0);
			
			float l_outline = L_OUTLINE - is_tiny*0.05;
			float l_glow = L_GLOW - is_tiny*0.05;
			
			vMapname = lerp(vMapname, L_OUTLINE_COLOUR, 1.0f - saturate( ( vDistance - l_outline ) / smoothing + l_outline ) );
			vMapname = lerp(vMapname, L_GLOW_COLOUR, 1.0f - saturate( ( vDistance - l_glow ) / smoothing + 0.5 ) );
			vMapname.a *= saturate( vDistance / l_outline ) * vTargetOpacity_Fade.x * vTargetOpacity_Fade.y;
			vMapname.rgb = ApplyDistanceFog( vMapname.rgb, v.vPrepos, GetFoWColor( v.vPrepos, FoWTexture), FoWDiffuse );
			
			/* See various mipmap levels. Uncomment this paragraph, comment out the above to see.
			float4 vMapname = float4(0.0,0.0,0.0, 0.99);
			if (lod < 1) {
				vMapname = float4(1,1,1,1); // white
			}
			else if (lod < 2) {
				vMapname = float4(1,0,1,1); // purple
			}
			else if (lod < 3) {
				vMapname = float4(1,1,0,1); // yellow
			}
			else if (lod < 4) {
				vMapname = float4(0,1,1,1); // cyan
			}
			else if (lod < 5) {
				vMapname = float4(0,0,1,1); // blue
			}
			else if (lod < 6) {
				vMapname = float4(1,0,0,1); //red
			}
			else if (lod < 7) {
				vMapname = float4(0,1,0,1); //green
			}*/
			return vMapname;
		}
	]]
}
// If you have any questions, please don't hesistate to contact me on Steam.
// - Moulton

## Blend States

BlendState BlendState
{
	AlphaTest = no
	WriteMask = "RED|GREEN|BLUE"
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"
	BlendEnable = yes
}

## Rasterizer States

## Depth Stencil States

## Effects

Effect mapname
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}