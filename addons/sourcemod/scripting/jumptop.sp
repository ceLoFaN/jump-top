// © Maxim "Kailo" Telezhenko, 2015
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>

#include <jumpstats>

#define ITEMS 10
#define STEAMID_LEN 18
#define NAME_LEN 40

new Handle:g_db = INVALID_HANDLE;
new Handle:g_confname = INVALID_HANDLE;
new Float:g_distances[sizeof(g_saJumpTypes)][ITEMS+1];
new bool:g_WriteExist[sizeof(g_saJumpTypes)][ITEMS+1];
new String:g_Names[sizeof(g_saJumpTypes)][ITEMS+1][NAME_LEN+1];
new String:g_SteamIds[sizeof(g_saJumpTypes)][ITEMS+1][STEAMID_LEN+1];

public Plugin:myinfo =
{
	name = "Jump Top",
	author = "Maxim 'Kailo' Telezhenko",
	description = "Jump rating",
	version = "alpha-0.0.1",
	url = "http://steamcommunity.com/id/kailo97/"
};

public OnPluginStart()
{
	LoadTranslations("jumptop.phrases");
	
	g_confname = CreateConVar("jumptop_confname", "", "Config name for SQL connect. If not stated — default.");
	AutoExecConfig(true);
	
	RegConsoleCmd("sm_ljtop", Command_Redict);
	RegConsoleCmd("sm_top", Command_Redict);
	RegConsoleCmd("sm_jumptop", Command_ShowTop);
	
	// Connect to db
	new String:error[255], String:confname[64];
	GetConVarString(g_confname, confname, 64);
	if (strlen(confname) == 0)
		confname = "default";
	g_db = SQL_Connect(confname, false, error, 255);
	if (g_db == INVALID_HANDLE) {
		LogError("Could not connect: %s", error);
	}
	
	// Check table exist
	for(new JumpType:jumptype = Jump_LJ;jumptype<Jump_End;jumptype++) {
		new String:tablename[64];
		Format(tablename, 64, "jumptop_%s", g_saJumpTypes[jumptype]);
		new String:query[255];
		Format(query, 255, "CREATE TABLE IF NOT EXISTS %s (place int(2) NOT NULL PRIMARY KEY, name varchar(%d) NOT NULL, steamid varchar(%d) NOT NULL, distance float(6,3) NOT NULL)", tablename, NAME_LEN, STEAMID_LEN);
		if (!SQL_FastQuery(g_db, query))
		{
			SQL_GetError(g_db, error, 255);
			LogError("Failed to query (error: %s)", error);
		}
	}
	
	// Get data from db
	for(new JumpType:jumptype = Jump_LJ;jumptype<Jump_End;jumptype++) {
		new String:tablename[64];
		Format(tablename, 64, "jumptop_%s", g_saJumpTypes[jumptype]);
		new String:queryline[255];
		Format(queryline, 255, "SELECT * FROM %s", tablename);
		new Handle:query = SQL_Query(g_db, queryline);
		if (query == INVALID_HANDLE)
		{
			SQL_GetError(g_db, error, 255);
			LogError("Failed to query (error: %s)", error);
		} else {
			if(SQL_GetRowCount(query) != 0) {
				while (SQL_FetchRow(query)) {
					new place = SQL_FetchInt(query, 0);
					g_WriteExist[jumptype][place] = true;
					SQL_FetchString(query, 1, g_Names[jumptype][place], NAME_LEN+1);
					SQL_FetchString(query, 2, g_SteamIds[jumptype][place], STEAMID_LEN+1);
					g_distances[jumptype][place] = SQL_FetchFloat(query, 3);
				}
			}
			CloseHandle(query);
		}
	}
}

/*
public bool:CheckConnection(String:error[], maxlength)
{
	if (g_db == INVALID_HANDLE) {
		p_error[maxlength+1];
		g_db = SQL_Connect(confname, false, p_error, sizeof(p_error));
		if (g_db == INVALID_HANDLE) {
			error = p_error;
			return false;
		}
		return true;
	}
	
	return true;
}
*/

public WriteRecordToDB(JumpType:type, place, const String:name[], const String:steamid[], Float:distance) {
	new String:tablename[64], String:error[255];
	Format(tablename, 64, "jumptop_%s", g_saJumpTypes[type]);
	new String:query[255];
	if(g_WriteExist[type][place])
		Format(query, 255, "UPDATE %s SET name='%s', steamid='%s', distance='%.3f' WHERE place=%d", tablename, name, steamid, distance, place);
	else {
		Format(query, 255, "INSERT INTO %s (place, name, steamid, distance) VALUES ('%d', '%s', '%s', '%.3f')", tablename, place, name, steamid, distance);
		g_WriteExist[type][place] = true;
	}
	if (!SQL_FastQuery(g_db, query))
	{
		SQL_GetError(g_db, error, 255);
		LogError("Failed to query (error: %s)", error);
	}
}

public OnJump(client, JumpType:type, Float:distance)
{
	// Check if new distance <= distance of 10th place, do nothing
	if(g_WriteExist[type][ITEMS] && distance <= g_distances[type][ITEMS])
		return;
	// Check if player already have record in top
	new String:name[NAME_LEN+1];
	GetClientName(client, name, NAME_LEN+1);
	new String:steamid[STEAMID_LEN+1];
	GetClientAuthId(client, AuthId_Steam2, steamid, STEAMID_LEN+1);
	for(new i=1;i<=ITEMS;i++) {
		if(strcmp(steamid, g_SteamIds[type][i]) == 0) {
			// if him new distance > old record
			if(distance > g_distances[type][i]) {
				// Store him current place
				new place = i;
				// If player's distance from next place < new distance, move player from next place to place lowwer, and up place for our player. Do it while him not be on 1st place or distance from next place be largest.
				while(place != 1 && distance > g_distances[type][place-1]) {
					WriteRecordToDB(type, place, g_Names[type][place-1], g_SteamIds[type][place-1], g_distances[type][place-1]);
					g_Names[type][place] = g_Names[type][place-1];
					g_SteamIds[type][place] = g_SteamIds[type][place-1];
					g_distances[type][place] = g_distances[type][place-1];
					place--;
				}
				// Write new record in db and annonce
				WriteRecordToDB(type, place, name, steamid, distance);
				g_Names[type][place] = name;
				g_SteamIds[type][place] = steamid;
				g_distances[type][place] = distance;
				PrintToChatAll("%t", "New Record", name, g_saPrettyJumpTypes[type], distance, place);
				return;
			}
			// if him new distance <= old record, do nothing 
			return;
		}
	}
	// If player haven't record in top
	new lastrealplace = 0;
	for(new i2=1;i2<=ITEMS;i2++) {
		if(g_WriteExist[type][i2]) {
			lastrealplace = i2;
		}
	}
	PrintToServer("%d", lastrealplace);
	if(lastrealplace != 0) {
		new place = lastrealplace + 1;
		while(place != 1 && distance > g_distances[type][place - 1]) {
			WriteRecordToDB(type, place, g_Names[type][place-1], g_SteamIds[type][place-1], g_distances[type][place-1]);
			g_Names[type][place] = g_Names[type][place-1];
			g_SteamIds[type][place] = g_SteamIds[type][place-1];
			g_distances[type][place] = g_distances[type][place-1];
			place--;
		}
		WriteRecordToDB(type, place, name, steamid, distance);
		g_Names[type][place] = name;
		g_SteamIds[type][place] = steamid;
		g_distances[type][place] = distance;
		PrintToChatAll("%t", "New Record", name, g_saPrettyJumpTypes[type], distance, place);
		return;
	}
	WriteRecordToDB(type, 1, name, steamid, distance);
	g_Names[type][1] = name;
	g_SteamIds[type][1] = steamid;
	g_distances[type][1] = distance;
	PrintToChatAll("%t", "New Record", name, g_saPrettyJumpTypes[type], distance, 1);
	return;
}

public Action:Command_Redict(client, args)
{
	ReplyToCommand(client, "Use /jumptop instead.");
}

public Action:Command_ShowTop(client, args)
{
	new Handle:menu = CreateMenu(TopMenuHandler);
	SetMenuTitle(menu, "What Jump Type?");
	for(new JumpType:jumptype = Jump_LJ;jumptype<Jump_End;jumptype++)
	{
		AddMenuItem(menu, g_saJumpTypes[jumptype], g_saJumpTypes[jumptype]);
	}
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, 10);
 
	return Plugin_Handled;
}

public TopMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_Select)
	{
		new Handle:panel = CreatePanel();
		new String:info[32];
		GetMenuItem(menu, param2, info, 32);
		SetPanelTitle(panel, info);
		for(new place=1;place<=ITEMS;place++) {
			new String:place_txt[3], String:buffer[128];
			(place<10) ? Format(place_txt, 3, "0%d", place) : Format(place_txt, 3, "%d", place);
			(place == ITEMS) ? Format(buffer, 128, "%s %.3f %s", place_txt, g_distances[param2+1][place], g_Names[param2+1][place]) : Format(buffer, 128, "%s %.3f %s\n", place_txt, g_distances[param2+1][place], g_Names[param2+1][place]);
			DrawPanelText(panel, buffer);
		}
		SendPanelToClient(panel, param1, TopPanelHandler, 10);
	}
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public TopPanelHandler(Handle:menu, MenuAction:action, param1, param2)
{
    //nothing to do
}  