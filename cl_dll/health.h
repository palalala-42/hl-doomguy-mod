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

#define DMG_IMAGE_LIFE		2	// seconds that image is up

#define DMG_IMAGE_POISON	0
#define DMG_IMAGE_ACID		1
#define DMG_IMAGE_COLD		2
#define DMG_IMAGE_DROWN		3
#define DMG_IMAGE_BURN		4
#define DMG_IMAGE_NERVE		5
#define DMG_IMAGE_RAD		6
#define DMG_IMAGE_SHOCK		7
//tf defines
#define DMG_IMAGE_CALTROP	8
#define DMG_IMAGE_TRANQ		9
#define DMG_IMAGE_CONCUSS	10
#define DMG_IMAGE_HALLUC	11
#define NUM_DMG_TYPES		12
// instant damage

#define DMG_GENERIC			0			// generic damage was done
#define DMG_CRUSH			(1 << 0)	// crushed by falling or moving object
#define DMG_BULLET			(1 << 1)	// shot
#define DMG_SLASH			(1 << 2)	// cut, clawed, stabbed
#define DMG_BURN			(1 << 3)	// heat burned
#define DMG_FREEZE			(1 << 4)	// frozen
#define DMG_FALL			(1 << 5)	// fell too far
#define DMG_BLAST			(1 << 6)	// explosive blast damage
#define DMG_CLUB			(1 << 7)	// crowbar, punch, headbutt
#define DMG_SHOCK			(1 << 8)	// electric shock
#define DMG_SONIC			(1 << 9)	// sound pulse shockwave
#define DMG_ENERGYBEAM		(1 << 10)	// laser or other high energy beam 
#define DMG_NEVERGIB		(1 << 12)	// with this bit OR'd in, no damage type will be able to gib victims upon death
#define DMG_ALWAYSGIB		(1 << 13)	// with this bit OR'd in, any damage type can be made to gib victims upon death.


// time-based damage
//mask off TF-specific stuff too
#define DMG_TIMEBASED		(~(0xff003fff))	// mask for time-based damage


#define DMG_DROWN			(1 << 14)	// Drowning
#define DMG_FIRSTTIMEBASED  DMG_DROWN

#define DMG_PARALYZE		(1 << 15)	// slows affected creature down
#define DMG_NERVEGAS		(1 << 16)	// nerve toxins, very bad
#define DMG_POISON			(1 << 17)	// blood poisioning
#define DMG_RADIATION		(1 << 18)	// radiation exposure
#define DMG_DROWNRECOVER	(1 << 19)	// drowning recovery
#define DMG_ACID			(1 << 20)	// toxic chemicals or acid burns
#define DMG_SLOWBURN		(1 << 21)	// in an oven
#define DMG_SLOWFREEZE		(1 << 22)	// in a subzero freezer
#define DMG_MORTAR			(1 << 23)	// Hit by air raid (done to distinguish grenade from mortar)

//TF ADDITIONS
#define DMG_IGNITE			(1 << 24)	// Players hit by this begin to burn
#define DMG_RADIUS_MAX		(1 << 25)	// Radius damage with this flag doesn't decrease over distance
#define DMG_RADIUS_QUAKE	(1 << 26)	// Radius damage is done like Quake. 1/2 damage at 1/2 radius.
#define DMG_IGNOREARMOR		(1 << 27)	// Damage ignores target's armor
#define DMG_AIMED			(1 << 28)   // Does Hit location damage
#define DMG_WALLPIERCING	(1 << 29)	// Blast Damages ents through walls

#define DMG_CALTROP				(1<<30)
#define DMG_HALLUC				(1<<31)

// TF Healing Additions for TakeHealth
#define DMG_IGNORE_MAXHEALTH	DMG_IGNITE
// TF Redefines since we never use the originals
#define DMG_NAIL				DMG_SLASH
#define DMG_NOT_SELF			DMG_FREEZE


#define DMG_TRANQ				DMG_MORTAR
#define DMG_CONCUSS				DMG_SONIC



typedef struct
{
	float fExpire;
	float fBaseline;
	int	x, y;
} DAMAGE_IMAGE;
	
//
// Doom viewmodels (Doomguy).  Sprites are built by tools/doom_weapon_sprites.ps1:
// every frame of one weapon is composited on ONE canvas (the union of the Doom
// patch offsets), so all frames share an anchor and the gun never jumps.
//
enum {
	DGUN_PUNG = 0,		// crowbar   -> Doom fist
	DGUN_PISG,			// 9mm, .357 -> Doom pistol
	DGUN_SHTG,			// shotgun   -> Doom shotgun
	DGUN_CHGG,			// MP5       -> Doom chaingun
	DGUN_MISG,			// RPG       -> Doom rocket launcher
	DGUN_PLSG,			// crossbow  -> Doom plasma rifle
	DGUN_BFGG,			// gauss     -> Doom BFG
	DGUN_COUNT
};
enum { DGUN_MAXFRAME = 5, DGUN_MAXFLASH = 4 };

// One animation per Half-Life weapon; the .357 reuses the pistol art with a
// slower rhythm, so it gets its own entry.
enum {
	DGANIM_GLOCK = 0,	// 9mm
	DGANIM_PYTHON,		// .357
	DGANIM_SHOTGUN,
	DGANIM_MP5,
	DGANIM_RPG,
	DGANIM_CROSSBOW,
	DGANIM_GAUSS,
	DGANIM_CROWBAR,
	DGANIM_COUNT
};

// Half-Life weapon ids, mirrored from dlls/weapons.h (the client dll cannot
// include that header).
enum {
	HLW_CROWBAR  = 1,
	HLW_GLOCK    = 2,
	HLW_PYTHON   = 3,
	HLW_MP5      = 4,
	HLW_CROSSBOW = 6,
	HLW_SHOTGUN  = 7,
	HLW_RPG      = 8,
	HLW_GAUSS    = 9
};

//
//-----------------------------------------------------
//
class CHudHealth: public CHudBase
{
public:
	virtual int Init( void );
	virtual int VidInit( void );
	virtual int Draw(float fTime);
	virtual void Reset( void );
	int MsgFunc_Health(const char *pszName,  int iSize, void *pbuf);
	int MsgFunc_Damage(const char *pszName,  int iSize, void *pbuf);
	int m_iHealth;
	int m_HUD_dmg_bio;
	int m_HUD_cross;
	HSPRITE m_hFaceSprite;
	// Doom face, animated. Frame layout built by tools/build_face_spr.ps1 (42 frames):
	enum {
		FACE_GAZE     = 0,	// 0..14  gaze direction, 3 per health level (level*3 + 0/1/2)
		FACE_OUCH     = 15,	// 15..19 grimace after a hard hit
		FACE_GRIN     = 20,	// 20..24 evil grin after picking up a weapon
		FACE_RAMPAGE  = 25,	// 25..29 rampage while the attack button is held
		FACE_GOD      = 30,	// 30     god mode (unused)
		FACE_DEAD     = 31,	// 31     dead
		FACE_TURNL    = 32,	// 32..36 turned left
		FACE_TURNR    = 37	// 37..41 turned right
	};
	float m_flFaceGrinUntil;	// m_flTime until which the pickup grin is shown
	float m_flFacePainUntil;	// m_flTime until which the grimace is shown
	int   m_iFacePainLevel;		// 0..4, grimace intensity
	float m_flFaceTurnUntil;	// m_flTime until which the turned face is shown
	int   m_iFaceTurnDir;		// -1 = left, +1 = right, 0 = none
	float m_flFaceHoldStart;	// when IN_ATTACK went down (-1 = not held)
	float m_flFaceGazeTime;		// next random gaze change
	int   m_iFaceGaze;			// current gaze variant 0..2
	int   m_iFaceDrawn;			// last drawn frame (-1 = none), log only
	void  NotifyWeaponPickup(void);
	int   FaceHealthLevel(void);
	int   DrawFace(float flTime);
	// Doom viewmodels: one shared canvas per weapon, so every frame keeps its anchor
	HSPRITE m_hDoomGun[DGUN_COUNT][DGUN_MAXFRAME];			// base frames, [0] = idle
	HSPRITE m_hDoomGunFlash[DGUN_COUNT][DGUN_MAXFLASH];		// muzzle flash frames
	float m_flGunFireTime;	// gHUD.m_flTime of the last Doom viewmodel shot
	int m_iGunAnim;			// DGANIM_* started by that shot (-1 = none)
	int m_iViewmodelState;	// last value we wrote to r_drawviewmodel (-1 = not set yet)
	void DrawGun(void);
	void StartGunFire(int iAnim);
	void UpdateViewmodel(void);
	int DoomGunAnimForWeapon(int iHlWeaponId);	// held HL weapon id -> DGANIM_*, -1 = none
	float m_fAttackFront, m_fAttackRear, m_fAttackLeft, m_fAttackRight;
	void GetPainColor( int &r, int &g, int &b );
	float m_fFade;

private:
	HSPRITE m_hSprite;
	HSPRITE m_hDamage;
	
	DAMAGE_IMAGE m_dmg[NUM_DMG_TYPES];
	int	m_bitsDamage;
	int DrawPain(float fTime);
	int DrawDamage(float fTime);
	void CalcDamageDirection(vec3_t vecFrom);
	void UpdateTiles(float fTime, long bits);
};	
