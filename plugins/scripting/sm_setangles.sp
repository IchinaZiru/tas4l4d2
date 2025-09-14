#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define MDL_NICK "models/survivors/survivor_gambler.mdl"
#define MDL_BILL "models/survivors/survivor_namvet.mdl"
#define MDL_ELIS "models/survivors/survivor_mechanic.mdl"
#define MDL_FRAN "models/survivors/survivor_biker.mdl"
#define MDL_COAC "models/survivors/survivor_coach.mdl"
#define MDL_LUIS "models/survivors/survivor_manager.mdl"
#define MDL_ROCH "models/survivors/survivor_producer.mdl"
#define MDL_ZOEY "models/survivors/survivor_teenangst.mdl"

public Plugin myinfo = {
	name = "Angle setter helper thing",
	author = "mike",
	description = "why is this even required",
	version = "1.1"
};

// feel free to lemme know if there's a better way to get client indices btw
int GetClient(char[] model1, char[] model2) {
	for (int i = 1; i < MaxClients; ++i) {
		if (IsClientInGame(i)) {
			char model[128];
			GetClientModel(i, model, sizeof(model));
			if (StrEqual(model, model1) || StrEqual(model, model2)) {
				return i;
			}
		}
	}
	return -1;
}

public void OnPluginStart() {
	RegConsoleCmd("sm_setangles", Cmd_Setangles, "set player view angles");
}

void PrintUsage(int client) {
	PrintToConsole(client, "usage: sm_setangles <nick|ellis|coach|rochelle> <p> <y> [r]");
}

float GetCmdArgFloat(int arg) {
	char val[128];
	GetCmdArg(arg, val, sizeof(val));
	return StringToFloat(val);
}

public Action Cmd_Setangles(int client, int args) {
	if (args != 3 && args != 4) {
		PrintUsage(client);
		return Plugin_Handled;
	}

	int target;
	char player[16];
	GetCmdArg(1, player, sizeof(player));
	if (StrEqual(player, "nick", false)) {
		target = GetClient(MDL_NICK, MDL_BILL);
	}
	else if (StrEqual(player, "ellis", false)) {
		target = GetClient(MDL_ELIS, MDL_FRAN);
	}
	else if (StrEqual(player, "coach", false)) {
		target = GetClient(MDL_COAC, MDL_LUIS);
	}
	else if (StrEqual(player, "rochelle", false)) {
		target = GetClient(MDL_ROCH, MDL_ZOEY);
	}
	else {
		PrintUsage(client);
		return Plugin_Handled;
	}
	
	if (target == -1) {
		PrintToConsole(client, "%s appears to not be in the server", player);
		return Plugin_Handled;
	}

	float angles[3];
	angles[0] = GetCmdArgFloat(2);
	angles[1] = GetCmdArgFloat(3);
	if (args == 4) {
		angles[2] = GetCmdArgFloat(4);
	}
	else {
		angles[2] = 0.0;
	}
	TeleportEntity(target, NULL_VECTOR, angles, NULL_VECTOR);
	return Plugin_Handled;
}