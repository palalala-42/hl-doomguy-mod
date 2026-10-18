/***
*
*	Copyright (c) 1996-2002, Valve LLC. All rights reserved.
*	
*	This product contains software technology licensed from Id 
*	Software, Inc. ("Id Technology").  Id Technology (c) 1996 Id Software, Inc. 
*	All Rights Reserved.
*
*   Use, distribution, and modification of this source code and/or resulting
*   object code is restricted to non-commercial enhancements to products from
*   Valve LLC.  All other use, distribution, or modification is prohibited
*   without written permission from Valve LLC.
*
****/
//
// Health.cpp
//
// implementation of CHudHealth class
//

#include "stdio.h"
#include "stdlib.h"
#include "math.h"

#include "hud.h"
#include "cl_util.h"
#include "parsemsg.h"
#include <string.h>


DECLARE_MESSAGE(m_Health, Health )
DECLARE_MESSAGE(m_Health, Damage )

#define PAIN_NAME "sprites/%d_pain.spr"
#define DAMAGE_NAME "sprites/%d_dmg.spr"

int giDmgHeight, giDmgWidth;

// ---------------------------------------------------------------------------
// Doom status bar (STBAR)
//
// Same pipeline as the viewmodels and the face: the Doom patch is baked at an
// on-screen scale and drawn as a sprite.  Doom's status bar is the bottom 32
// rows of the 320x200 screen (st_stuff.c: ST_Y = 168), so at scale 2.5/3.0 it is
// 800x96 at the bottom of an 800x600 screen - and the gun baseline below is
// exactly its top edge, because in Doom the psprite is clipped to the 168 line
// view window.
//
// Sprites are pixel art and the engine draws them 1:1 (there is no scaled sprite
// draw in the client API), so one set of sprites exists per scale.  A Doom pixel
// is 6/5 as tall as it is wide, so the x scale is an integer and the y scale is
// always 1.2 * x; the sets are named dg<TAG>_* with TAG = 10 * x (dg20, dg25,
// dg30, dg40, dg50).  DoomPickScale() runs first in VidInit: it takes the
// biggest set that still fits the screen and that really exists on disk, so the
// bar keeps the same share of every screen and a missing set degrades to a
// smaller one (or to the plain Half-Life HUD) instead of drawing nothing.
//
// Widget coordinates are Doom's own (bar top = 168), from st_stuff.c/st_lib.c:
//    ST_AMMOX 44   y 171     ST_HEALTHX 90  + '%' AT 90     ST_ARMORX 221 + '%'
//    ST_ARMORY 171           ST_FACESX 143 / ST_FACESY 168  tallnum cell 14x16
// STlib_drawNum() right-aligns the digits (x -= w before every digit) and
// STlib_updatePercent() draws the '%' patch AT n->x, so the numbers above are
// the RIGHT edges of the number blocks.
// ---------------------------------------------------------------------------
bool g_bDoomStatusBar = false;	// set in VidInit; battery.cpp/ammo.cpp read it
int  g_iDoomArmor = 0;		// published by CHudBattery::Draw
int  g_iDoomAmmo = 0;		// published by CHudAmmo::Draw

// Current Doom -> screen scale.  The scale tag names the sprite set, so every
// Doom sprite of the mod is sprites/dg<TAG>_*: dg25_stbar, dg25_pct, dg25_face,
// dg25_num and the viewmodels dg25_<key>_<frame> / dg25_<key>_f<frame>.
float g_flDoomScaleX = 2.5f;		// Doom pixel -> screen pixel, x
float g_flDoomScaleY = 3.0f;		// ... and y (always 1.2 * g_flDoomScaleX)
int   g_iDoomScaleTag = 25;		// 10 * g_flDoomScaleX, used in the file names

static HSPRITE s_hDoomBar = 0;	// sprites/dg<TAG>_stbar.spr  STBAR    320x32
static HSPRITE s_hDoomPct = 0;	// sprites/dg<TAG>_pct.spr    STTPRCNT  14x16

#define DOOMBAR_X(v)	((int)((v) * g_flDoomScaleX + 0.5f))
#define DOOMBAR_Y(v)	((int)((v) * g_flDoomScaleY + 0.5f))

// The face canvas anchor is (0,1) in Doom units and the bar's top edge is Doom
// row 168 (ST_Y), so the face offset is measured from there:
//   x: ST_FACESX 143 + anchor 0
//   y: (ST_FACESY 168 + anchor 1) - ST_Y 168
#define DOOMFACE_X	((int)(143 * g_flDoomScaleX + 0.5f))
#define DOOMFACE_Y	((int)(1   * g_flDoomScaleY + 0.5f))

// The viewmodel is cut off at the bar's top edge (Doom's psprite is clipped to
// row 168), i.e. its baseline is the bar height.
#define DOOMGUN_BASELINE ((int)(32 * g_flDoomScaleY + 0.5f))

int giDmgFlags[NUM_DMG_TYPES] = 
{
	DMG_POISON,
	DMG_ACID,
	DMG_FREEZE|DMG_SLOWFREEZE,
	DMG_DROWN,
	DMG_BURN|DMG_SLOWBURN,
	DMG_NERVEGAS, 
	DMG_RADIATION,
	DMG_SHOCK,
	DMG_CALTROP,
	DMG_TRANQ,
	DMG_CONCUSS,
	DMG_HALLUC
};

// ---------------------------------------------------------------------------
// Doom viewmodels
//
// Sprites come from tools/doom_weapon_sprites.ps1: all frames of one weapon are
// composited on a single canvas (the union of the Doom patch left/top offsets),
// so the frames line up and the gun never jumps.
//
// Placement is exactly Doom's: a patch pixel i with patch offset "left" lands at
//     screen_x = ScreenWidth/2 - Sx * (160.5 + left - i)
// which is what flCenterX/flCanvasW below reproduce: 160.5 is the Doom screen
// centre in psprite units, and the canvas starts at the smallest -left.
// ---------------------------------------------------------------------------

typedef struct
{
	const char *pszKey;		// sprite name: sprites/dg_<key>_<a..e>.spr
	int iFrames;			// number of base frames
	int iFlash;				// number of flash frames (sprites/dg_<key>_f<a..d>.spr)
	float flCenterX;		// gun centre inside the canvas (psprite units)
	float flCanvasW;		// canvas size in psprite units
	float flCanvasH;
} DOOMGUNDEF;

static const DOOMGUNDEF s_doomGun[DGUN_COUNT] =
{
	// key    frames flash  centerX  canvas W  canvas H
	{ "pung",    4,    0,   124.5f,   228.0f,    76.0f },
	{ "pisg",    5,    1,    56.5f,    82.0f,   103.0f },
	{ "shtg",    4,    2,   131.5f,   171.0f,   151.0f },
	{ "chgg",    2,    2,    56.5f,   114.0f,   103.0f },
	{ "misg",    2,    4,    48.5f,   105.0f,   119.0f },
	{ "plsg",    2,    2,    96.5f,   143.0f,   111.0f },
	{ "bfgg",    3,    2,    79.5f,   170.0f,   123.0f }
};

// One animation phase: from the previous phase end until flEnd, draw base frame
// iFrame plus (if >= 0) flash frame iFlash.  Once the last phase is over (up to
// flTotal) the weapon shows its idle frame again.
typedef struct { float flEnd; signed char iFrame; signed char iFlash; } DOOMGUNPHASE;

typedef struct
{
	int iWeapon;					// DGUN_* slot
	float flTotal;					// animation length in seconds
	int iPhases;
	const DOOMGUNPHASE *pPhases;
} DOOMGUNANIM;

// Doom's tic counts (35 tics/s) scaled into the Half-Life fire interval of each
// weapon; the idle frame fills whatever is left of that interval.
// 9mm pistol: HL cycle 0.2 s
static const DOOMGUNPHASE s_phaseGlock[] =
{
	{ 0.055f, 0, 0 },	// A + PISFA0
	{ 0.095f, 1, -1 },	// B
	{ 0.135f, 2, -1 },	// C
	{ 0.170f, 3, -1 },	// D
	{ 0.200f, 4, -1 }	// E
};

// .357: HL cycle 0.75 s, same art as the 9mm but slower
static const DOOMGUNPHASE s_phasePython[] =
{
	{ 0.090f, 0, 0 },
	{ 0.200f, 1, -1 },
	{ 0.350f, 2, -1 },
	{ 0.500f, 3, -1 },
	{ 0.620f, 4, -1 }
};

// shotgun: HL cycle 0.75 s (verified look), 34 Doom tics scaled into it
static const DOOMGUNPHASE s_phaseShotgun[] =
{
	{ 0.088f, 0, 0 },	// idle A + SHTFA0
	{ 0.154f, 0, 1 },	// idle A + SHTFB0
	{ 0.265f, 1, -1 },	// B
	{ 0.375f, 2, -1 },	// C
	{ 0.463f, 3, -1 },	// D
	{ 0.574f, 2, -1 },	// C
	{ 0.684f, 1, -1 }	// B
};

// MP5: HL cycle 0.1 s; the Doom chaingun keeps its barrels spinning (frame B)
// from the first shot until the trigger is released
static const DOOMGUNPHASE s_phaseMp5[] =
{
	{ 0.030f, 1, 0 },	// B + CHGFA0
	{ 0.060f, 1, 1 },	// B + CHGFB0
	{ 0.100f, 1, -1 }	// B
};

// RPG: HL cycle ~1 s; the 4 Doom backblast frames
static const DOOMGUNPHASE s_phaseRpg[] =
{
	{ 0.070f, 0, 0 },	// A + MISFA0
	{ 0.140f, 1, 1 },	// B + MISFB0
	{ 0.210f, 1, 2 },	// B + MISFC0
	{ 0.300f, 1, 3 },	// B + MISFD0
	{ 0.550f, 1, -1 }	// B
};

// crossbow: HL cycle 0.75 s; the plasma rifle stands in as the energy weapon
static const DOOMGUNPHASE s_phaseCrossbow[] =
{
	{ 0.060f, 0, 0 },	// A + PLSFA0
	{ 0.120f, 1, 1 },	// B + PLSFB0
	{ 0.350f, 1, -1 }	// B
};

// gauss: HL cycle 0.5 s; BFG firing frames
static const DOOMGUNPHASE s_phaseGauss[] =
{
	{ 0.080f, 0, 0 },	// A + BFGFA0
	{ 0.180f, 2, 1 },	// C + BFGFB0
	{ 0.300f, 1, -1 }	// B
};

// crowbar: HL swing 0.5 s; the Doom fist punch swings the arm across
static const DOOMGUNPHASE s_phaseCrowbar[] =
{
	{ 0.150f, 1, -1 },	// B
	{ 0.300f, 2, -1 },	// C
	{ 0.450f, 3, -1 }	// D
};

// order must match the DGANIM_* enum
static const DOOMGUNANIM s_doomAnim[DGANIM_COUNT] =
{
	{ DGUN_PISG, 0.20f, 5, s_phaseGlock },
	{ DGUN_PISG, 0.75f, 5, s_phasePython },
	{ DGUN_SHTG, 0.75f, 7, s_phaseShotgun },
	{ DGUN_CHGG, 0.10f, 3, s_phaseMp5 },
	{ DGUN_MISG, 1.00f, 5, s_phaseRpg },
	{ DGUN_PLSG, 0.75f, 3, s_phaseCrossbow },
	{ DGUN_BFGG, 0.50f, 3, s_phaseGauss },
	{ DGUN_PUNG, 0.50f, 3, s_phaseCrowbar }
};

int CHudHealth::Init(void)
{
	HOOK_MESSAGE(Health);
	HOOK_MESSAGE(Damage);
	m_iHealth = 100;
	m_fFade = 0;
	m_hFaceSprite = 0;
	m_flFaceGrinUntil = -1.0f;
	m_flFacePainUntil = -1.0f;
	m_iFacePainLevel = 0;
	m_flFaceTurnUntil = -1.0f;
	m_iFaceTurnDir = 0;
	m_flFaceHoldStart = -1.0f;
	m_flFaceGazeTime = 0.0f;
	m_iFaceGaze = 0;
	m_iFaceDrawn = -1;
	memset(m_hDoomGun, 0, sizeof(m_hDoomGun));
	memset(m_hDoomGunFlash, 0, sizeof(m_hDoomGunFlash));
	m_flGunFireTime = -1000.0f;
	m_iGunAnim = -1;
	m_iViewmodelState = -1;
	m_iFlags = 0;
	m_bitsDamage = 0;
	m_fAttackFront = m_fAttackRear = m_fAttackRight = m_fAttackLeft = 0;
	giDmgHeight = 0;
	giDmgWidth = 0;

	memset(m_dmg, 0, sizeof(DAMAGE_IMAGE) * NUM_DMG_TYPES);


	gHUD.AddHudElem(this);
	return 1;
}

void CHudHealth::Reset( void )
{
	// make sure the pain compass is cleared when the player respawns
	m_fAttackFront = m_fAttackRear = m_fAttackRight = m_fAttackLeft = 0;

	// Doom face: drop every transient expression on respawn
	m_flFaceGrinUntil = -1.0f;
	m_flFacePainUntil = -1.0f;
	m_iFacePainLevel = 0;
	m_flFaceTurnUntil = -1.0f;
	m_iFaceTurnDir = 0;
	m_flFaceHoldStart = -1.0f;
	m_flFaceGazeTime = 0.0f;	// also re-arm the idle gaze (idle changes every 0.5 s)
	m_iFaceGaze = 0;
	m_iFaceDrawn = -1;
	m_flGunFireTime = -1000.0f;
	m_iGunAnim = -1;


	// force all the flashing damage icons to expire
	m_bitsDamage = 0;
	for ( int i = 0; i < NUM_DMG_TYPES; i++ )
	{
		m_dmg[i].fExpire = 0;
	}
}

// ---------------------------------------------------------------------------
// The scale sets that exist, largest last.  x scale 2.0/2.5/3.0/4.0/5.0 with
// y = 1.2 * x: 640x480, 800x600, 1024x768, 1280x960 and 1920x1080 (and every
// other mode in between, which snaps down to the biggest set that fits).
// ---------------------------------------------------------------------------
static const int s_iDoomScaleTags[] = { 20, 25, 30, 40, 50 };

// Choose the sprite set for the current screen.  Runs in CHud::VidInit before
// any Doom sprite is loaded, so the bar, the face, the digits and the viewmodels
// always agree on one scale.
void DoomPickScale(void)
{
	// m_scrinfo/ScreenWidth are already set by the time VidInit runs, but ask the
	// engine directly so this cannot depend on when it is called.
	SCREENINFO si;
	memset(&si, 0, sizeof(si));
	si.iSize = sizeof(si);
	GetScreenInfo(&si);

	int iW = si.iWidth  > 0 ? si.iWidth  : ScreenWidth;
	int iH = si.iHeight > 0 ? si.iHeight : ScreenHeight;
	if (iW <= 0 || iH <= 0)
		return;					// no layout yet - keep the defaults

	int iCount = (int)(sizeof(s_iDoomScaleTags) / sizeof(s_iDoomScaleTags[0]));
	int iPick = -1, iSmallest = -1;

	for (int i = iCount - 1; i >= 0; i--)
	{
		float sx = s_iDoomScaleTags[i] / 10.0f;
		float sy = sx * 1.2f;			// a Doom pixel is 6/5 as tall as it is wide

		char szPath[64];
		sprintf(szPath, "sprites/dg%d_stbar.spr", s_iDoomScaleTags[i]);
		if (!SPR_Load(szPath))
			continue;			// this set was not built - try a smaller one

		if (iSmallest < 0)
			iSmallest = i;

		if (320.0f * sx <= (float)iW && 32.0f * sy <= (float)iH)
		{
			iPick = i;
			break;
		}
	}

	// Screen smaller than every set (or no set at all): the smallest one still
	// beats nothing, and the engine clips what does not fit.
	if (iPick < 0)
		iPick = iSmallest;

	if (iPick >= 0)
	{
		g_iDoomScaleTag = s_iDoomScaleTags[iPick];
		g_flDoomScaleX  = g_iDoomScaleTag / 10.0f;
		g_flDoomScaleY  = g_flDoomScaleX * 1.2f;
	}

	gEngfuncs.Con_Printf("doomhud: screen %dx%d -> tag %d scale %.2f/%.2f (bar %dx%d)\n",
		iW, iH, g_iDoomScaleTag, g_flDoomScaleX, g_flDoomScaleY,
		DOOMBAR_X(320), DOOMBAR_Y(32));
}

int CHudHealth::VidInit(void)
{
	m_hSprite = 0;

	// Doom viewmodels: one canvas per weapon, built by tools/doom_weapon_sprites.ps1
	{
		char szPath[64];
		for (int i = 0; i < DGUN_COUNT; i++)
		{
			for (int f = 0; f < DGUN_MAXFRAME; f++)
			{
				m_hDoomGun[i][f] = 0;
				if (f < s_doomGun[i].iFrames)
				{
					sprintf(szPath, "sprites/dg%d_%s_%c.spr", g_iDoomScaleTag, s_doomGun[i].pszKey, 'a' + f);
					m_hDoomGun[i][f] = gEngfuncs.pfnSPR_Load(szPath);
				}
			}
			for (int f = 0; f < DGUN_MAXFLASH; f++)
			{
				m_hDoomGunFlash[i][f] = 0;
				if (f < s_doomGun[i].iFlash)
				{
					sprintf(szPath, "sprites/dg%d_%s_f%c.spr", g_iDoomScaleTag, s_doomGun[i].pszKey, 'a' + f);
					m_hDoomGunFlash[i][f] = gEngfuncs.pfnSPR_Load(szPath);
				}
			}
			gEngfuncs.Con_Printf("doomgun %s tag %d: idle=%p size=%dx%d frames=%d flash=%d\n",
				s_doomGun[i].pszKey, g_iDoomScaleTag, m_hDoomGun[i][0],
				SPR_Width(m_hDoomGun[i][0], 0), SPR_Height(m_hDoomGun[i][0], 0),
				s_doomGun[i].iFrames, s_doomGun[i].iFlash);
		}
	}

	// The face, the bar and the '%' patch come from the same set as the digits
	// (dg<TAG>_face / dg<TAG>_stbar / dg<TAG>_pct), all picked in CHud::VidInit.
	char szDoom[64];
	sprintf(szDoom, "sprites/dg%d_face.spr", g_iDoomScaleTag);
	m_hFaceSprite = gEngfuncs.pfnSPR_Load(szDoom);

	// Doom status bar: the bar itself and the '%' patch (the digits come from
	// gHUD.m_hDoomNumber, which CHud::VidInit has already loaded).
	sprintf(szDoom, "sprites/dg%d_stbar.spr", g_iDoomScaleTag);
	s_hDoomBar = gEngfuncs.pfnSPR_Load(szDoom);
	sprintf(szDoom, "sprites/dg%d_pct.spr", g_iDoomScaleTag);
	s_hDoomPct = gEngfuncs.pfnSPR_Load(szDoom);

	// Only hide the Half-Life readouts when the bar is really there, so a
	// missing sprite degrades to the plain HL HUD instead of an empty one.
	g_bDoomStatusBar = (s_hDoomBar != 0);

	gEngfuncs.Con_Printf("doomstbar tag %d: bar=%p %dx%d pct=%p %dx%d num cell=%dx%d bar=%d scale=%.2f/%.2f\n",
		g_iDoomScaleTag,
		s_hDoomBar, SPR_Width(s_hDoomBar, 0), SPR_Height(s_hDoomBar, 0),
		s_hDoomPct, SPR_Width(s_hDoomPct, 0), SPR_Height(s_hDoomPct, 0),
		gHUD.m_iDoomNumWidth, gHUD.m_iDoomNumHeight, (int)g_bDoomStatusBar,
		g_flDoomScaleX, g_flDoomScaleY);

	// A level change (or a save load) invalidates every sprite handle and restarts
	// the HUD clock.  ResetHUD may arrive on either side of VidInit, so drop all
	// face/gun animation state here too: an expression stored as an absolute time
	// would otherwise stay armed against a clock that has jumped backwards.
	m_flFaceGrinUntil = -1.0f;
	m_flFacePainUntil = -1.0f;
	m_iFacePainLevel = 0;
	m_flFaceTurnUntil = -1.0f;
	m_iFaceTurnDir = 0;
	m_flFaceHoldStart = -1.0f;
	m_flFaceGazeTime = 0.0f;
	m_iFaceGaze = 0;
	m_iFaceDrawn = -1;
	m_flGunFireTime = -1000.0f;

	gEngfuncs.Con_Printf("doomface spr loaded: %p, size=%dx%d frames=%d t=%.1f\n",
		m_hFaceSprite, SPR_Width(m_hFaceSprite,0), SPR_Height(m_hFaceSprite,0),
		(m_hFaceSprite ? SPR_Frames(m_hFaceSprite) : 0), gHUD.m_flTime);

	m_HUD_dmg_bio = gHUD.GetSpriteIndex( "dmg_bio" ) + 1;
	m_HUD_cross = gHUD.GetSpriteIndex( "cross" );

	giDmgHeight = gHUD.GetSpriteRect(m_HUD_dmg_bio).right - gHUD.GetSpriteRect(m_HUD_dmg_bio).left;
	giDmgWidth = gHUD.GetSpriteRect(m_HUD_dmg_bio).bottom - gHUD.GetSpriteRect(m_HUD_dmg_bio).top;
	return 1;
}

int CHudHealth:: MsgFunc_Health(const char *pszName,  int iSize, void *pbuf )
{
	// TODO: update local health data
	BEGIN_READ( pbuf, iSize );
	int x = READ_BYTE();

	m_iFlags |= HUD_ACTIVE;

	// Only update the fade if we've changed health
	if (x != m_iHealth)
	{
		m_fFade = FADE_TIME;
		m_iHealth = x;
	}

	return 1;
}


int CHudHealth:: MsgFunc_Damage(const char *pszName,  int iSize, void *pbuf )
{
	BEGIN_READ( pbuf, iSize );

	int armor = READ_BYTE();	// armor
	int damageTaken = READ_BYTE();	// health
	long bitsDamage = READ_LONG(); // damage bits

	vec3_t vecFrom;

	for ( int i = 0 ; i < 3 ; i++)
		vecFrom[i] = READ_COORD();

	UpdateTiles(gHUD.m_flTime, bitsDamage);

	// Actually took damage?
	if ( damageTaken > 0 || armor > 0 )
		CalcDamageDirection(vecFrom);

	// Doom face reactions (priorities as in Doom):
	//   hard hit (>20 at once) -> grimace, light hit -> look toward the attacker
	if ( damageTaken > 0 )
	{
		if ( damageTaken > 20 )
		{
			m_flFacePainUntil = gHUD.m_flTime + 1.4f;	// Doom PAINTIME
			if ( damageTaken <= 40 )
				m_iFacePainLevel = 0;
			else if ( damageTaken <= 60 )
				m_iFacePainLevel = 1;
			else if ( damageTaken <= 80 )
				m_iFacePainLevel = 2;
			else if ( damageTaken <= 100 )
				m_iFacePainLevel = 3;
			else
				m_iFacePainLevel = 4;
		}
		else if ( m_fAttackLeft > m_fAttackRight )
		{
			m_iFaceTurnDir = -1;
			m_flFaceTurnUntil = gHUD.m_flTime + 1.0f;
		}
		else if ( m_fAttackRight > m_fAttackLeft )
		{
			m_iFaceTurnDir = 1;
			m_flFaceTurnUntil = gHUD.m_flTime + 1.0f;
		}
	}

	return 1;
}


// Returns back a color from the
// Green <-> Yellow <-> Red ramp
void CHudHealth::GetPainColor( int &r, int &g, int &b )
{
	int iHealth = m_iHealth;

	if (iHealth > 25)
		iHealth -= 25;
	else if ( iHealth < 0 )
		iHealth = 0;
#if 0
	g = iHealth * 255 / 100;
	r = 255 - g;
	b = 0;
#else
	if (m_iHealth > 25)
	{
		UnpackRGB(r,g,b, RGB_YELLOWISH);
	}
	else
	{
		r = 250;
		g = 0;
		b = 0;
	}
#endif 
}

// ---------------------------------------------------------------------------
// Doom status bar drawing
// ---------------------------------------------------------------------------

// One right-aligned (up to) 3 digit Doom number with an optional '%' after it.
// x is the right edge of the number in screen pixels, y the digit top.
static void DrawDoomBarNumber(int x, int y, int iValue, bool bPercent)
{
	int iWidth = gHUD.m_iDoomNumWidth;

	// The tallnum patches are Doom's own red, so draw them untinted; the digits
	// are right aligned, and DrawDoomNumber reserves a cell for every missing
	// digit, so starting 3 cells to the left is exactly STlib_drawNum's layout.
	gHUD.DrawDoomNumber(x - 3 * iWidth, y, DHN_3DIGITS | DHN_DRAWZERO, iValue, 255, 255, 255);

	if (bPercent && s_hDoomPct)
	{
		// STlib_updatePercent() draws the patch AT the number's right edge
		SPR_Set(s_hDoomPct, 255, 255, 255);
		SPR_DrawHoles(0, x, y, NULL);
	}
}

static void DrawDoomStatusBar(int iHealth)
{
	if (!g_bDoomStatusBar || !s_hDoomBar)
		return;

	int barW = SPR_Width(s_hDoomBar, 0);
	int barH = SPR_Height(s_hDoomBar, 0);
	int barX = (ScreenWidth - barW) / 2;
	int barY = ScreenHeight - barH;

	SPR_Set(s_hDoomBar, 255, 255, 255);
	SPR_DrawHoles(0, barX, barY, NULL);

	// Doom row 171 is the top of the tall digits (3 rows below the bar top).
	// DrawDoomNumber() bottom-aligns its glyphs to the Half-Life font, so give
	// it the y that makes its own baseline land on the Doom row.
	int yTall = barY + DOOMBAR_Y(171 - 168);
	int yNum  = yTall + gHUD.m_iDoomNumHeight - gHUD.m_iFontHeight;

	DrawDoomBarNumber(barX + DOOMBAR_X(44),  yNum, g_iDoomAmmo,  false);	// ST_AMMOX
	DrawDoomBarNumber(barX + DOOMBAR_X(90),  yNum, iHealth,      true);	// ST_HEALTHX
	DrawDoomBarNumber(barX + DOOMBAR_X(221), yNum, g_iDoomArmor, true);	// ST_ARMORX
}

int CHudHealth::Draw(float flTime)
{
	int r, g, b;
	int a = 0, x, y;
	int HealthWidth;

	if ( (gHUD.m_iHideHUDDisplay & HIDEHUD_HEALTH) || gEngfuncs.IsSpectateOnly() )
		return 1;

	if ( !m_hSprite )
		m_hSprite = LoadSprite(PAIN_NAME);
	
	// Has health changed? Flash the health #
	if (m_fFade)
	{
		m_fFade -= (gHUD.m_flTimeDelta * 20);
		if (m_fFade <= 0)
		{
			a = MIN_ALPHA;
			m_fFade = 0;
		}

		// Fade the health number back to dim

		a = MIN_ALPHA +  (m_fFade/FADE_TIME) * 128;

	}
	else
		a = MIN_ALPHA;

	// If health is getting low, make it bright red
	if (m_iHealth <= 15)
		a = 255;
		
	GetPainColor( r, g, b );
	ScaleColors(r, g, b, a );

	// The Doom status bar replaces the Half-Life health cross and number (the
	// armor and ammo readouts are suppressed in battery.cpp / ammo.cpp).
	DrawDoomStatusBar(m_iHealth);

	// Doomguy viewmodel: Doom shotgun sprite, drawn only while the shotgun is held.
	DrawGun();

	// Doom-like animated face in center bottom
	DrawFace(flTime);

	DrawDamage(flTime);
	return DrawPain(flTime);
}

// ---------------------------------------------------------------------------
// Doom viewmodel drawing
//
// The per-weapon tables (s_doomGun / s_doomAnim) are at the top of this file;
// every weapon uses the same placement rule and the same canvas bottom line.
// ---------------------------------------------------------------------------
// The viewmodel is cut off at the status bar's top edge (DOOMGUN_BASELINE), so
// the gun disappears behind the bar exactly like Doom's psprite at row 168.
#define GUN_BASELINE	DOOMGUN_BASELINE

int CHudHealth::DoomGunAnimForWeapon(int iHlWeaponId)
{
	switch (iHlWeaponId)
	{
	case HLW_CROWBAR:	return DGANIM_CROWBAR;
	case HLW_GLOCK:		return DGANIM_GLOCK;
	case HLW_PYTHON:	return DGANIM_PYTHON;
	case HLW_MP5:		return DGANIM_MP5;
	case HLW_SHOTGUN:	return DGANIM_SHOTGUN;
	case HLW_CROSSBOW:	return DGANIM_CROSSBOW;
	case HLW_RPG:		return DGANIM_RPG;
	case HLW_GAUSS:		return DGANIM_GAUSS;
	}

	// everything else (egon, hornetgun, grenades, satchel, snark, tripmine)
	// keeps the Half-Life viewmodel
	return -1;
}

void CHudHealth::StartGunFire(int iAnim)
{
	if (iAnim < 0 || iAnim >= DGANIM_COUNT)
		return;

	float dt = gHUD.m_flTime - m_flGunFireTime;

	// Client-side prediction and the server can both raise the very same shot;
	// only a repeat within the same frames is a duplicate.  Real shots are at
	// least 0.1 s apart (MP5), so this can never eat a genuine shot.
	if (iAnim == m_iGunAnim && dt >= 0.0f && dt < 0.04f)
		return;

	m_flGunFireTime = gHUD.m_flTime;
	m_iGunAnim = iAnim;

	// Console report of one shot: which frame/flash is shown when
	const DOOMGUNANIM *pa = &s_doomAnim[iAnim];
	char szPhases[256];
	szPhases[0] = 0;
	for (int i = 0; i < pa->iPhases; i++)
	{
		char szOne[40];
		sprintf(szOne, " %c%s@%.3f", 'A' + pa->pPhases[i].iFrame,
			(pa->pPhases[i].iFlash >= 0) ? "+f" : "", pa->pPhases[i].flEnd);
		strcat(szPhases, szOne);
	}

	static int s_iShots = 0;
	s_iShots++;
	gEngfuncs.Con_Printf("gunfire #%d %s t=%.3f total=%.3f |%s\n",
		s_iShots, s_doomGun[pa->iWeapon].pszKey, gHUD.m_flTime, pa->flTotal, szPhases);
}

void CHudHealth::UpdateViewmodel(void)
{
	WEAPON *pWeapon = gHUD.m_Ammo.GetCurrentWeapon();
	int iAnim = pWeapon ? DoomGunAnimForWeapon(pWeapon->iId) : -1;

	int want = (iAnim >= 0) ? 0 : 1;	// 0 = we draw the Doom viewmodel instead
	if (want != m_iViewmodelState)
	{
		m_iViewmodelState = want;
		gEngfuncs.Cvar_SetValue("r_drawviewmodel", (float)want);
	}
}

void CHudHealth::DrawGun(void)
{
	WEAPON *pWeapon = gHUD.m_Ammo.GetCurrentWeapon();
	int iAnim = pWeapon ? DoomGunAnimForWeapon(pWeapon->iId) : -1;
	if (iAnim < 0)
		return;

	const DOOMGUNANIM *pa = &s_doomAnim[iAnim];
	const DOOMGUNDEF  *pd = &s_doomGun[pa->iWeapon];

	HSPRITE hIdle = m_hDoomGun[pa->iWeapon][0];
	if (!hIdle)
		return;

	int gw = SPR_Width(hIdle, 0);
	int gh = SPR_Height(hIdle, 0);

	// Doom placement: the canvas column at the screen centre is flCenterX
	int gx = ScreenWidth / 2 - (int)(gw * pd->flCenterX / pd->flCanvasW + 0.5f);

	// The gun sits on the bar's top edge: use the sprite that was really loaded,
	// so a missing bar cannot push the viewmodel off the screen.
	int iBase = s_hDoomBar ? SPR_Height(s_hDoomBar, 0) : GUN_BASELINE;
	int gy = (ScreenHeight - iBase) - gh;
	if (gy < 0) gy = 0;

	int frame = 0;
	int flash = -1;

	// Only animate the shot that belongs to the weapon being held
	if (iAnim == m_iGunAnim)
	{
		float elapsed = gHUD.m_flTime - m_flGunFireTime;
		if (elapsed >= 0.0f && elapsed < pa->flTotal)
		{
			for (int i = 0; i < pa->iPhases; i++)
			{
				if (elapsed < pa->pPhases[i].flEnd)
				{
					frame = pa->pPhases[i].iFrame;
					flash = pa->pPhases[i].iFlash;
					break;
				}
			}
		}
	}

	HSPRITE h = m_hDoomGun[pa->iWeapon][frame];
	if (!h)
		h = hIdle;

	SPR_Set(h, 255, 255, 255);
	SPR_DrawHoles(0, gx, gy, NULL);

	if (flash >= 0 && m_hDoomGunFlash[pa->iWeapon][flash])
	{
		SPR_Set(m_hDoomGunFlash[pa->iWeapon][flash], 255, 255, 255);
		SPR_DrawHoles(0, gx, gy, NULL);
	}
}

// ---------------------------------------------------------------------------
// Doom face
//
// Frames come from one multi-frame sprite (tools/build_face_spr.ps1); every
// frame shares the same 32x32 canvas, so the head never jumps.
// Priority follows Doom: death, pickup grin, pain (grimace or look toward the
// attacker), rampage, then a random gaze direction.
// ---------------------------------------------------------------------------

int CHudHealth::FaceHealthLevel(void)
{
	if (m_iHealth >= 80)	return 0;
	if (m_iHealth >= 60)	return 1;
	if (m_iHealth >= 40)	return 2;
	if (m_iHealth >= 20)	return 3;
	return 4;
}

void CHudHealth::NotifyWeaponPickup(void)
{
	m_flFaceGrinUntil = gHUD.m_flTime + 2.0f;
}

int CHudHealth::DrawFace(float flTime)
{
	float now = gHUD.m_flTime;
	int lvl = FaceHealthLevel();
	int frame;
	const char *why;

	// The engine's HUD clock restarts when the map changes (and on a save load).
	// Every expression below is stored as an absolute time, so anything still
	// "in the future" would latch forever; detect the backwards jump and drop it.
	static float s_flFaceLastTime = 0.0f;
	static int   s_iFaceStuckFrame = -1;
	static float s_flFaceStuckSince = 0.0f;
	if (s_flFaceLastTime > 0.0f && now + 0.5f < s_flFaceLastTime)
	{
		gEngfuncs.Con_Printf("[face] hud clock re-based %.1f -> %.1f, clearing face state\n", s_flFaceLastTime, now);
		m_flFaceGrinUntil = -1.0f;
		m_flFacePainUntil = -1.0f;
		m_flFaceTurnUntil = -1.0f;
		m_iFaceTurnDir = 0;
		m_flFaceHoldStart = -1.0f;
		m_flFaceGazeTime = 0.0f;
		m_flGunFireTime = -1000.0f;
	}
	s_flFaceLastTime = now;

	if (m_iHealth <= 0)
	{
		frame = FACE_DEAD;
		why = "dead";
	}
	else if (m_flFaceGrinUntil > now)
	{
		frame = FACE_GRIN + lvl;
		why = "grin (weapon pickup)";
	}
	else if (m_flFacePainUntil > now)
	{
		frame = FACE_OUCH + m_iFacePainLevel;
		why = "grimace (hard hit)";
	}
	else if (m_flFaceTurnUntil > now && m_iFaceTurnDir != 0)
	{
		frame = ((m_iFaceTurnDir < 0) ? FACE_TURNL : FACE_TURNR) + lvl;
		why = (m_iFaceTurnDir < 0) ? "turn left (hit from the left)" : "turn right (hit from the right)";
	}
	else
	{
		// rampage: attack button held continuously for 2 s
		if (gHUD.m_iKeyBits & IN_ATTACK)
		{
			if (m_flFaceHoldStart < 0)
				m_flFaceHoldStart = now;
		}
		else
		{
			m_flFaceHoldStart = -1.0f;
		}

		if (m_flFaceHoldStart >= 0 && (now - m_flFaceHoldStart) >= 2.0f)
		{
			frame = FACE_RAMPAGE + lvl;
			why = "rampage (fire held)";
		}
		else
		{
			if (now >= m_flFaceGazeTime)
			{
				m_iFaceGaze = gEngfuncs.pfnRandomLong(0, 2);
				m_flFaceGazeTime = now + 0.5f;
			}
			frame = FACE_GAZE + lvl * 3 + m_iFaceGaze;
			why = "idle (gaze)";
		}
	}

	if (frame != m_iFaceDrawn)
	{
		gEngfuncs.Con_Printf("doomface: frame=%d lvl=%d hp=%d %s\n", frame, lvl, m_iHealth, why);
		m_iFaceDrawn = frame;
		s_iFaceStuckFrame = frame;
		s_flFaceStuckSince = now;
	}
	else if (frame == s_iFaceStuckFrame && (now - s_flFaceStuckSince) >= 2.0f)
	{
		// diagnostic: the same face held for 2 s -> dump what drives it (idle changes every 0.5 s)
		gEngfuncs.Con_Printf("[face] held %.1fs: frame=%d lvl=%d hp=%d %s | t=%.1f gazeT=%.1f grinT=%.1f painT=%.1f turnT=%.1f holdStart=%.1f bits=0x%x\n",
			now - s_flFaceStuckSince, frame, lvl, m_iHealth, why, now,
			m_flFaceGazeTime, m_flFaceGrinUntil, m_flFacePainUntil, m_flFaceTurnUntil, m_flFaceHoldStart, gHUD.m_iKeyBits);
		s_flFaceStuckSince = now;
	}

	{
		int faceW = DOOMBAR_X(32);
		int faceH = DOOMBAR_Y(32);
		if (m_hFaceSprite)
		{
			faceW = SPR_Width(m_hFaceSprite, 0);
			faceH = SPR_Height(m_hFaceSprite, 0);
		}

		// The face sits in the status bar's face box: the canvas anchor is Doom's
		// (ST_FACESX, ST_FACESY + canvas anchor), scaled the same way as the bar.
		int barW = s_hDoomBar ? SPR_Width(s_hDoomBar, 0) : DOOMBAR_X(320);
		int barH = s_hDoomBar ? SPR_Height(s_hDoomBar, 0) : DOOMBAR_Y(32);

		int faceX = (ScreenWidth - barW) / 2 + DOOMFACE_X;
		int faceY = ScreenHeight - barH + DOOMFACE_Y;

		if (m_hFaceSprite)
		{
			wrect_t rc;
			rc.left = 0;
			rc.right = faceW;
			rc.top = 0;
			rc.bottom = faceH;
			SPR_Set(m_hFaceSprite, 255, 255, 255);
			SPR_DrawHoles(frame, faceX, faceY, &rc);
		}
		else
		{
			int r = 0, g = 255, b = 0;
			if (m_iHealth <= 20) { r = 128; g = 0; b = 0; }
			else if (m_iHealth <= 40) { r = 255; g = 0; b = 0; }
			else if (m_iHealth <= 60) { r = 255; g = 160; b = 0; }
			else if (m_iHealth <= 80) { r = 255; g = 255; b = 0; }
			FillRGBA(faceX, faceY, faceW, faceH, r, g, b, 200);
		}
	}

	return 1;
}

void CHudHealth::CalcDamageDirection(vec3_t vecFrom)
{
	vec3_t	forward, right, up;
	float	side, front;
	vec3_t vecOrigin, vecAngles;

	if (!vecFrom[0] && !vecFrom[1] && !vecFrom[2])
	{
		m_fAttackFront = m_fAttackRear = m_fAttackRight = m_fAttackLeft = 0;
		return;
	}


	memcpy(vecOrigin, gHUD.m_vecOrigin, sizeof(vec3_t));
	memcpy(vecAngles, gHUD.m_vecAngles, sizeof(vec3_t));


	VectorSubtract (vecFrom, vecOrigin, vecFrom);

	float flDistToTarget = vecFrom.Length();

	vecFrom = vecFrom.Normalize();
	AngleVectors (vecAngles, forward, right, up);

	front = DotProduct (vecFrom, right);
	side = DotProduct (vecFrom, forward);

	if (flDistToTarget <= 50)
	{
		m_fAttackFront = m_fAttackRear = m_fAttackRight = m_fAttackLeft = 1;
	}
	else 
	{
		if (side > 0)
		{
			if (side > 0.3)
				m_fAttackFront = max(m_fAttackFront, side);
		}
		else
		{
			float f = fabs(side);
			if (f > 0.3)
				m_fAttackRear = max(m_fAttackRear, f);
		}

		if (front > 0)
		{
			if (front > 0.3)
				m_fAttackRight = max(m_fAttackRight, front);
		}
		else
		{
			float f = fabs(front);
			if (f > 0.3)
				m_fAttackLeft = max(m_fAttackLeft, f);
		}
	}
}

int CHudHealth::DrawPain(float flTime)
{
	if (!(m_fAttackFront || m_fAttackRear || m_fAttackLeft || m_fAttackRight))
		return 1;

	int r, g, b;
	int x, y, a, shade;

	// TODO:  get the shift value of the health
	a = 255;	// max brightness until then

	float fFade = gHUD.m_flTimeDelta * 2;
	
	// SPR_Draw top
	if (m_fAttackFront > 0.4)
	{
		GetPainColor(r,g,b);
		shade = a * max( m_fAttackFront, 0.5f );
		ScaleColors(r, g, b, shade);
		SPR_Set(m_hSprite, r, g, b );

		x = ScreenWidth/2 - SPR_Width(m_hSprite, 0)/2;
		y = ScreenHeight/2 - SPR_Height(m_hSprite,0) * 3;
		SPR_DrawAdditive(0, x, y, NULL);
		m_fAttackFront = max( 0.0f, m_fAttackFront - fFade );
	} else
		m_fAttackFront = 0;

	if (m_fAttackRight > 0.4)
	{
		GetPainColor(r,g,b);
		shade = a * max( m_fAttackRight, 0.5f );
		ScaleColors(r, g, b, shade);
		SPR_Set(m_hSprite, r, g, b );

		x = ScreenWidth/2 + SPR_Width(m_hSprite, 1) * 2;
		y = ScreenHeight/2 - SPR_Height(m_hSprite,1)/2;
		SPR_DrawAdditive(1, x, y, NULL);
		m_fAttackRight = max( 0.0f, m_fAttackRight - fFade );
	} else
		m_fAttackRight = 0;

	if (m_fAttackRear > 0.4)
	{
		GetPainColor(r,g,b);
		shade = a * max( m_fAttackRear, 0.5f );
		ScaleColors(r, g, b, shade);
		SPR_Set(m_hSprite, r, g, b );

		x = ScreenWidth/2 - SPR_Width(m_hSprite, 2)/2;
		y = ScreenHeight/2 + SPR_Height(m_hSprite,2) * 2;
		SPR_DrawAdditive(2, x, y, NULL);
		m_fAttackRear = max( 0.0f, m_fAttackRear - fFade );
	} else
		m_fAttackRear = 0;

	if (m_fAttackLeft > 0.4)
	{
		GetPainColor(r,g,b);
		shade = a * max( m_fAttackLeft, 0.5f );
		ScaleColors(r, g, b, shade);
		SPR_Set(m_hSprite, r, g, b );

		x = ScreenWidth/2 - SPR_Width(m_hSprite, 3) * 3;
		y = ScreenHeight/2 - SPR_Height(m_hSprite,3)/2;
		SPR_DrawAdditive(3, x, y, NULL);

		m_fAttackLeft = max( 0.0f, m_fAttackLeft - fFade );
	} else
		m_fAttackLeft = 0;

	return 1;
}

int CHudHealth::DrawDamage(float flTime)
{
	int r, g, b, a;
	DAMAGE_IMAGE *pdmg;

	// The Half-Life damage-type tiles sit in the bottom left corner, which the
	// Doom status bar now occupies (Doom has no equivalent readout).
	if (g_bDoomStatusBar)
		return 1;

	if (!m_bitsDamage)
		return 1;

	UnpackRGB(r,g,b, RGB_YELLOWISH);
	
	a = (int)( fabs(sin(flTime*2)) * 256.0);

	ScaleColors(r, g, b, a);

	// Draw all the items
	int i;
	for ( i = 0; i < NUM_DMG_TYPES; i++)
	{
		if (m_bitsDamage & giDmgFlags[i])
		{
			pdmg = &m_dmg[i];
			SPR_Set(gHUD.GetSprite(m_HUD_dmg_bio + i), r, g, b );
			SPR_DrawAdditive(0, pdmg->x, pdmg->y, &gHUD.GetSpriteRect(m_HUD_dmg_bio + i));
		}
	}


	// check for bits that should be expired
	for ( i = 0; i < NUM_DMG_TYPES; i++ )
	{
		DAMAGE_IMAGE *pdmg = &m_dmg[i];

		if ( m_bitsDamage & giDmgFlags[i] )
		{
			pdmg->fExpire = min( flTime + DMG_IMAGE_LIFE, pdmg->fExpire );

			if ( pdmg->fExpire <= flTime		// when the time has expired
				&& a < 40 )						// and the flash is at the low point of the cycle
			{
				pdmg->fExpire = 0;

				int y = pdmg->y;
				pdmg->x = pdmg->y = 0;

				// move everyone above down
				for (int j = 0; j < NUM_DMG_TYPES; j++)
				{
					pdmg = &m_dmg[j];
					if ((pdmg->y) && (pdmg->y < y))
						pdmg->y += giDmgHeight;

				}

				m_bitsDamage &= ~giDmgFlags[i];  // clear the bits
			}
		}
	}

	return 1;
}
 

void CHudHealth::UpdateTiles(float flTime, long bitsDamage)
{	
	DAMAGE_IMAGE *pdmg;

	// Which types are new?
	long bitsOn = ~m_bitsDamage & bitsDamage;
	
	for (int i = 0; i < NUM_DMG_TYPES; i++)
	{
		pdmg = &m_dmg[i];

		// Is this one already on?
		if (m_bitsDamage & giDmgFlags[i])
		{
			pdmg->fExpire = flTime + DMG_IMAGE_LIFE; // extend the duration
			if (!pdmg->fBaseline)
				pdmg->fBaseline = flTime;
		}

		// Are we just turning it on?
		if (bitsOn & giDmgFlags[i])
		{
			// put this one at the bottom
			pdmg->x = giDmgWidth/8;
			pdmg->y = ScreenHeight - giDmgHeight * 2;
			pdmg->fExpire=flTime + DMG_IMAGE_LIFE;
			
			// move everyone else up
			for (int j = 0; j < NUM_DMG_TYPES; j++)
			{
				if (j == i)
					continue;

				pdmg = &m_dmg[j];
				if (pdmg->y)
					pdmg->y -= giDmgHeight;

			}
			pdmg = &m_dmg[i];
		}	
	}	

	// damage bits are only turned on here;  they are turned off when the draw time has expired (in DrawDamage())
	m_bitsDamage |= bitsDamage;
}
