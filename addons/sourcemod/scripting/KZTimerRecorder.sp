#define DEBUG
#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_AUTHOR "Ruto"
#define PLUGIN_VERSION "0.01"

#define TICK_DATA_BLOCKSIZE 7
#define REPLAY_MAGIC_NUMBER 0x676F6B7A // 0x7275746F6B7A :(
#define REPLAY_FORMAT_VERSION 0x01
#define REPLAY_DIRECTORY "data/kztimer-ruto-replays"

// SOURCEMOD INCLUDES
#include <sourcemod>
#include <sdktools>
#include <cstrike>

// KZTIMER INCLUDES
#include <kztimer>

bool g_bRecording[MAXPLAYERS + 1];
ArrayList g_tickData[MAXPLAYERS + 1];
char g_sMapName[64];

public Plugin myinfo = 
{
	name = "Ruto KZTimer Recorder",
	author = PLUGIN_AUTHOR,
	description = "Records replays to the same format as GOKZ",
	version = PLUGIN_VERSION,
	url = "https://github.com/RutoTV/KZTimerRecorder"
};

public void OnPluginStart()
{
	// Check if we are on CSGO
	if(GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");	
	}

	// Register commands
	RegConsoleCmd("sm_rrv", Command_Version, "Get Ruto's KZTimer Recorder version");
}

public void OnAllPluginsLoaded()
{	
	// find kztimer name
	if (!LibraryExists("KZTimer")) 
	{
		SetFailState("GOKZ-core and GOKZ-localranks is required to run this plugin!");
	}
	
	// Load current clients if any
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (!IsValidClient(i)) continue;
	}
}

// REF: https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/gokz-replays.sp?at=master&fileviewer=file-view-default#gokz-replays.sp-276
public void OnMapStart()
{
	GetCurrentMap(g_sMapName, sizeof(g_sMapName));
	GetMapDisplayName(g_sMapName, g_sMapName, sizeof(g_sMapName));
	String_ToLower(g_sMapName, g_sMapName, sizeof(g_sMapName));

	CreateReplaysDirectory(g_sMapName);
}

/* 
	IDK SOMETHING 
*/
void StartRecording(int client) 
{
	if (IsFakeClient(client)) return;
	// Stop OnPlayerRunCmd from recording
	StopRecording(client);
	g_tickData[client].Clear();

	g_bRecording[client] = true;
}

void StopRecording(int client) 
{
	g_bRecording[client] = false;
}

// REFERENCE https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/gokz-replays/recording.sp?at=master&fileviewer=file-view-default#recording.sp-36
bool SaveRecording(int client, int teleports, float time) 
{
	if (!g_bRecording[client])
	{
		return false;
	}
	
	// Prepare data
	int mode = 2; // KZT mode in GOKZ
	int style = 0; // IDK
	int course = 0; // main course = 0
	bool isPro = teleports == 0;
	
	// Setup file path and file
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), 
		"%s/%s/%d_%s_%s_%s.%s", 
		REPLAY_DIRECTORY, g_sMapName, course, "KZT", "NRM", isPro ? "PRO" : "NUB", "replay");
	if (FileExists(path))
	{
		DeleteFile(path);
	}
	
	File file = OpenFile(path, "wb");
	if (file == null)
	{
		LogError("Couldn't create/open replay file to write to: %s", path);
		return false;
	}
	
	// Prepare more data
	char steamID2[24], ip[16], alias[MAX_NAME_LENGTH];
	GetClientAuthId(client, AuthId_Steam2, steamID2, sizeof(steamID2));
	GetClientIP(client, ip, sizeof(ip));
	GetClientName(client, alias, sizeof(alias));
	int tickCount = g_tickData[client].Length;
	
	// Write header
	file.WriteInt32(REPLAY_MAGIC_NUMBER);
	file.WriteInt8(REPLAY_FORMAT_VERSION);
	file.WriteInt8(strlen(PLUGIN_VERSION));
	file.WriteString(PLUGIN_VERSION, false);
	file.WriteInt8(strlen(g_sMapName));
	file.WriteString(g_sMapName, false);
	file.WriteInt32(course);
	file.WriteInt32(mode);
	file.WriteInt32(style);
	file.WriteInt32(view_as<int>(time));
	file.WriteInt32(teleports);
	file.WriteInt32(GetSteamAccountID(client));
	file.WriteInt8(strlen(steamID2));
	file.WriteString(steamID2, false);
	file.WriteInt8(strlen(ip));
	file.WriteString(ip, false);
	file.WriteInt8(strlen(alias));
	file.WriteString(alias, false);
	file.WriteInt32(tickCount);
	
	// Write tick data
	any tickData[TICK_DATA_BLOCKSIZE];
	for (int i = 0; i < tickCount; i++)
	{
		g_tickData[client].GetArray(i, tickData, TICK_DATA_BLOCKSIZE);
		file.Write(tickData, TICK_DATA_BLOCKSIZE, 4);
	}
	file.Close();
	
	// Discard recorded data
	g_tickData[client].Clear();
	g_bRecording[client] = false;
	
	return true;
}

/* 
	EVENT HANDLERS 
*/

// REFERENCE: https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/gokz-replays/recording.sp?at=master&fileviewer=file-view-default#recording.sp-227
public Action OnPlayerRunCmd(
	int client,
	int &buttons, 
	int &impulse, 
	float vels[3], //vel[3]
	float angles2[3], 
	int &weapon, 
	int &subtype, 
	int &cmdnum, 
	int &tickcount, 
	int &seed, 
	int mouse[2]) 
{
	if (IsFakeClient(client))
	{
		return;
	}

	if (g_bRecording[client] && !IsPaused(client))
	{
		int tick = GetArraySize(g_tickData[client]);
		g_tickData[client].Resize(tick + 1);
		
		float origin[3], angles[3];
		GetClientAbsOrigin(client, origin);
		GetClientEyeAngles(client, angles);
		int flags = GetEntityFlags(client);
		
		g_tickData[client].Set(tick, origin[0], 0);
		g_tickData[client].Set(tick, origin[1], 1);
		g_tickData[client].Set(tick, origin[2], 2);
		g_tickData[client].Set(tick, angles[0], 3);
		g_tickData[client].Set(tick, angles[1], 4);
		// Don't bother tracking eye angle roll (angles[2]) - not used
		g_tickData[client].Set(tick, buttons, 5);
		g_tickData[client].Set(tick, flags, 6);
	}
}

public void KZTimer_TimerStarted(int client) 
{
	if (g_tickData[client] == INVALID_HANDLE)
	{
		OnClientPutInServer(client);
	}
	StartRecording(client);
}

public void KZTimer_TimerStopped(int client, int teleports, float time, bool record) 
{
	record = true;
	if (record) 
	{
		SaveRecording(client, teleports, time);
	}
	StopRecording(client);
}

public void KZTimer_TimerStoppedValid(int client, int teleports, int rank, float time) 
{
	StopRecording(client);
}

public void OnClientPutInServer(int client) 
{
	if (g_tickData[client] == INVALID_HANDLE)
	{
		g_tickData[client] = new ArrayList(TICK_DATA_BLOCKSIZE, 0);
	}
	else
	{
		g_tickData[client].Clear();
	}
}

public void OnClientDisconnect(int client) 
{
	if (!IsValidClient(client)) return;

	StopRecording(client);
}

/* 
	COMMAND HANDLERS
*/
public Action Command_Version(int client, int args) {
	ReplyToCommand(client, "Ruto KZTimer Recorder Version %s", PLUGIN_VERSION);
	return Plugin_Handled;
}

/*
	Helpers
*/
// From https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/include/gokz.inc?at=master&fileviewer=file-view-default#gokz.inc-121
bool IsValidClient(int client)
{
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client);
}

// REFERENCE https://bitbucket.org/kztimerglobalteam/kztimerglobal/src/c59dd71859aefdc7c9e69d9e03aa596c39391643/scripting/kztimerGlobal/commands.sp?at=master&fileviewer=file-view-default#commands.sp-1786
bool IsPaused(int client) 
{
	// MOVETYPE_NONE occurs when paused, or challenged
	return GetEntityMoveType(client) == MOVETYPE_NONE;
}

// REF: https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/include/gokz.inc?at=master&fileviewer=file-view-default#gokz.inc-198
void String_ToLower(const char[] input, char[] output, int size)
{
	size--;
	int i = 0;
	while (input[i] != '\0' && i < size)
	{
		output[i] = CharToLower(input[i]);
		i++;
	}
	output[i] = '\0';
}

// REF: https://bitbucket.org/kztimerglobalteam/gokz/src/3b49c655ec18631939d69ce64b511a90e560f5a7/addons/sourcemod/scripting/gokz-replays.sp?at=master&fileviewer=file-view-default#gokz-replays.sp-283
static void CreateReplaysDirectory(const char[] map)
{
	char path[PLATFORM_MAX_PATH];
	
	// Create parent replay directory
	BuildPath(Path_SM, path, sizeof(path), REPLAY_DIRECTORY);
	if (!DirExists(path))
	{
		CreateDirectory(path, 511);
	}
	
	// Create map's replay directory
	BuildPath(Path_SM, path, sizeof(path), "%s/%s", REPLAY_DIRECTORY, map);
	if (!DirExists(path))
	{
		CreateDirectory(path, 511);
	}
}
