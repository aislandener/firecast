require("scene.lua");
require("utils.lua");
require("async.lua");
require("firecast.lua");
require("locale.lua");
local VHD = require("vhd.lua");
local NDB = require("ndb.lua");
local Log = require("log.lua");

--- local to remote data migration

local TOKENS_LOG_VERBOSE = true;
local TOKENS_LOG_TAG = 'tokens';
local TOKENS_REMOTE_NAME = 'tokens';
local TOKENS_LOCAL_FILENAME = 'inseridor.xml';

local function log_verbose(msg)
	if TOKENS_LOG_VERBOSE then
		Log.i(TOKENS_LOG_TAG, msg);
	end;
end;

local function migrateLocalToRemoteNDB(localFileName, remoteNDB)
	assert(remoteNDB ~= nil);
	
	if remoteNDB.__migratedFromLocal then
		return remoteNDB;
	end;
	
	if VHD.fileExists(localFileName) then
		log_verbose("Local tokens file exists");
	
		local bkpFileName = localFileName .. ".bkp";
		
		if not VHD.fileExists(bkpFileName) then
			log_verbose("local tokens backup file does not exists. Creating it...")
			VHD.copyFile(localFileName, bkpFileName);
		end;
		
		assert(VHD.fileExists(bkpFileName));	
		
		if not remoteNDB.__migratedFromLocal then
			Log.i(TOKENS_LOG_TAG, "remote tokens NDB was not yet migrated from local. Migrating...");
		
			local localNDB = NDB.load(localFileName);
			assert(localNDB ~= nil);
			
			Locale.withNoEval(
				function()				
					local savedXML = NDB.exportXML(localNDB);
					NDB.importXML(remoteNDB, savedXML);
				end);
			
			remoteNDB.__migratedFromLocal = true;
		else
			log_verbose("remote tokens ndb was already migrated");
		end;
	else	
		log_verbose("No local tokens file, no migration is needed");
		remoteNDB.__migratedFromLocal = true;
	end;
	
	return remoteNDB;
end;

local function asyncStartLocalToRemoteDataMigration()
	local promise = Firecast.asyncOpenUserNDB(TOKENS_REMOTE_NAME, {create=true});
	
	promise:thenDo(
		function(remoteTokens)
			migrateLocalToRemoteNDB(TOKENS_LOCAL_FILENAME, remoteTokens)
		end);
end;

--- main body of the "insert" plugin

SceneLib.registerPlugin(
	function (scene, attachment)
		local frmInserior = nil;
		local timeoutClearFrmGenerator = nil;
		local lastFrm;

		local function openPopUP(form)	
			if not scene.isGM then
				showMessage(lang("scene.inseridor.alert.gm.only"));
				return;
			end;

			if timeoutClearFrmGenerator ~= nil then
				clearTimeout(timeoutClearFrmGenerator);						
				timeoutClearFrmGenerator = nil;
			end;	

			local frm;		
			local dataPromise;

			if frmInserior == nil or lastFrm ~= form then	
				lastFrm = form;			
				frm = GUI.newForm(form);
				
				asyncStartLocalToRemoteDataMigration();
				dataPromise = Firecast.asyncOpenUserNDB(TOKENS_REMOTE_NAME, {create=true, skipLoad=true});				
			else
				frm = frmInserior;
				dataPromise = Promise.resolved(frm:getNodeObject());
			end
			
			local function continueFrmShowWithNode(node)
				frm:setNodeObject(node);
					
				if (not frm.isShowing) then
					frm:prepareForShow(scene);									  				    
					frm:show();
				end;
			end;
			
			dataPromise:thenDo(
				function (node)
					continueFrmShowWithNode(node);		
				end,
				
				function(errorMsg)
					Log.e(TOKENS_LOG_TAG, "Could not open user ndb: " .. errorMsg .. ". Falling back to local storage");
					continueFrmShowWithNode(NDB.load(TOKENS_LOCAL_FILENAME));
				end);		
			
			frmInserior = frm;
			
			timeoutClearFrmGenerator = setTimeout(
				function()
					frmInserior = nil;
				end, 5 * 60 * 1000);  -- 5 minutos			
		end;

		scene.viewport:setupToolCategory("Inseridor", lang("scene.inseridor.name"), -8);
		
		scene.viewport:addToolButton("Inseridor", 
		        lang("scene.inseridor.library"), 
				 "/icos/token.png",
				 -5,
				 {},
				 function()
					openPopUP("frmInseriorFireDrive");
				 end);

		scene.viewport:addToolButton("Inseridor", 
		        lang("scene.magic.title"), 
				 "/icos/magic.png",
				 -5,
				 {},
				 function()
					openPopUP("frmMagicTokens");
				 end);
		
		scene.viewport:addToolButton("Inseridor", 
		        lang("scene.inseridor.pc"), 
				 "/icos/pc.png",
				 -5,
				 {},
				 function()
					Dialogs.openFile(lang("scene.inseridor.instruction"), "image/*", false,
				        function(arquivos)
				                local arq = arquivos[1];

				                FireDrive.createDirectory("/uploads");

				                local date_table = os.date("*t")
				                local subfolder = date_table.year .. date_table.month;

				                FireDrive.createDirectory("/uploads/" .. subfolder);

				                FireDrive.upload("/uploads/" .. subfolder .. "/" .. arq.name, arq.stream,
				                	function(fditem)
				                		local token = scene.items:addToken("tokens");

										local _lastMouseDown = rawget(scene, "_lastMouseDown");
									
										if _lastMouseDown ~= nil then
											token.x = _lastMouseDown.x;
											token.y = _lastMouseDown.y;
										else
											token.x = scene.worldWidth / 2;
											token.y = scene.worldHeight / 2;		
										end;

										token.image.url = fditem.url;
										token.name = fditem.name;
										token.selected = true;
				                	end);          
				        end);
				 end);

		scene.viewport:addToolButton("Inseridor", 
		        lang("scene.inseridor.www"), 
				 "/icos/www.png",
				 -5,
				 {},
				 function()
					Dialogs.selectImageURL("", 
				        function(url)
				            local token = scene.items:addToken("tokens");

							local _lastMouseDown = rawget(scene, "_lastMouseDown");
							
							if _lastMouseDown ~= nil then
								token.x = _lastMouseDown.x;
								token.y = _lastMouseDown.y;
							else
								token.x = scene.worldWidth / 2;
								token.y = scene.worldHeight / 2;		
							end;

							token.image.url = url;
							token.selected = true;   
				        end);
				 end);

		scene.viewport:addToolButton("Inseridor", 
		        lang("scene.inseridor.players"), 
				 "/icos/player.png",
				 -5,
				 {},
				 function()
					local mesa = Firecast.getMesaDe(scene);
					local usuarios = mesa.jogadores;
					local ctrl = 0;
					for i=1, #usuarios, 1 do
						if usuarios[i].isJogador then
							local jogador = usuarios[i];
							local per = jogador.personagemPrincipal;
							local size = scene.grid.cellSize;

							local token = scene.items:addToken("tokens");

							local _lastMouseDown = rawget(scene, "_lastMouseDown");
							
							if _lastMouseDown ~= nil then
								token.x = _lastMouseDown.x + (ctrl * size);
								token.y = _lastMouseDown.y;
							else
								token.x = scene.worldWidth / 2 + (ctrl * size);
								token.y = scene.worldHeight / 2;		
							end;

							token.image.url = jogador.avatar;
							token.name = Utils.removerFmtChat(jogador.nick, true);
							token.ownerCharacter = per;
							token.ownerUserID = jogador.login;

							ctrl = ctrl +1;
						end;
					end;
					if ctrl < 1 then
						showMessage(lang("scene.inseridor.noplayers"));
					end;
				 end);	
	end);