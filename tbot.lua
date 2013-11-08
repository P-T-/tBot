-- by PixelToast (ping,pong)
-- some of the cleanest and fully commented code you will ever see

-- so how are you holding up
local socket=require("socket")
local http=require("socket.http")
local url=require("socket.url")
local ltn12=require("ltn12")
local config
do
	local oprint=print
	function print(txt)
		local m=txt:gsub("\27","")
		oprint(m)
	end
	local file=io.open("tBot-config.txt","r")
	local defconfig='vernum=0,\nversion="0",\nnsuser=nil,\nnick="tBot",\nchan="#tbot",\nnetwork="178.79.153.80",\nnetport="6667",'
	if file then
		config=loadstring("return {"..file:read("*a").."}")()
		file:close()
		if not config.nsuser then
			print("Edit config!")
			os.exit()
		end
	else
		file=io.open("tBot-config.txt","w")
		file:write(defconfig)
		file:close()
		print("Edit config!")
		os.exit()
	end
end
local sv
local cnick=config.nick
local function connect()
	print("connecting")
	if sv then
		sv:close()
	end
	while true do
		sv=socket.connect(config.network,config.netport)
		if sv then
			print("connected")
			sv:send("NICK "..config.nick.."\r\nUSER tBot tBot tBot :ping's bot\r\n")
			return
		end
		socket.sleep(5)
		print("retrying")
	end
end
local function savecfg()
	file=io.open("tBot-config.txt","w")
	for k,v in pairs(config) do
		file:write(k.."=")
		if type(v)=="string" then
			file:write("\""..string.format("%q",v).."\",\n")
		else
			file:write(tostring(v)..",\n")
		end
	end
	file:close()
end
local parsecmd
do
	local cmdat
	local pfx=""
	local function say(txt)
		if cmdat.chan==cnick then
			sv:send("PRIVMSG "..cmdat.nick.." :"..pfx..txt.."\r\n")
		else
			sv:send("PRIVMSG "..cmdat.chan.." :"..pfx..txt.."\r\n")
		end
	end
	local short={
		["s"]="server",
		["w"]="wiki",
		["t"]="tell",
	}
	local cmds
	cmds={
		["help"]=function()
			say("Commands: tell, help, server, wiki | Test commands in PM first!")
		end,
		["ping"]=function()
			say("pong")
		end,
		["server"]=function(dat)
			local m={}
			for ma in dat:gmatch("%S+") do
				m[#m+1]=ma
			end
			if #m>2 or #m<1 then
				say("Usage: .server <ip> [port]")
				return
			end
			m[2]=tonumber(m[2] or "7777")
			if not m[2] then
				say("Invalid port!")
				return
			end
			if m[2]>65535 or m[2]<1024 then
				say("Port out of allowed range!")
				return
			end
			local n=socket.dns.toip(m[1])
			if not n then
				say("Could not resolve address!")
				return
			end
			local s=socket.tcp()
			s:settimeout(0.5)
			local sv=s:connect(n,m[2])
			if not sv then
				say("Could not connect!")
				return
			end
			local pa="\1Terraria"..config.vernum
			s:send(string.char(#pa).."\0\0\0"..pa)
			local pk=s:receive(5)
			if not pk then
				say("Could not connect!")
				return
			end
			pk=pk:sub(5)
			if pk=="\3" then
				say("Server running and updated to "..config.version)
			elseif pk=="\2" then
				say("Server running but outdated (<"..config.version..")")
			else
				say("Unknown response code: 0x"..string.format("%X",string.byte(pk)))
			end
		end,
		["setversion"]=function(dat)
			local m={}
			for ma in dat:gmatch("%S+") do
				m[#m+1]=ma
			end
			if #m~=2 then
				say("Usage: .setversion <number> <name> ; Example: 71 1.2.0.3.1")
				return
			end
			m[1]=tonumber(m[1])
			if not m[1] then
				say("Invalid version number!")
				return
			end
			config.vernum=m[1]
			config.version=m[2]
			savecfg()
			say("Version set!")
		end,
		["wiki"]=function(dat)
			if #dat:gsub("%s","")==0 then
				say(cmdat.nick..", Usage: .wiki <search>")
				return
			end
			dat=url.escape(dat)
			local t={}
			local r=http.request({
				url="http://terraria.gamepedia.com/"..dat,
				headers={["User-Agent"]="tBot"},
				sink=ltn12.sink.table(t),
			})
			local c=table.concat(t)
			if not c:find('<div class="noarticletext">\n<p>There is currently no text in this page.') then
				local ur=c:match('<meta name="og:url" content="http://terraria%.gamepedia%.com/(.-)" />')
				if ur then
					say("http://terraria.gamepedia.com/"..ur)
					return
				end
			end
			t={}
			r=http.request({
				url="http://terraria.gamepedia.com/api.php?limit=1&action=opensearch&search="..dat,
				headers={["User-Agent"]="tBot"},
				sink=ltn12.sink.table(t),
			})
			if r then
				local _,m=table.concat(t):match("%[\"(.+)\",%[\"(.+)\"%]%]")
				if m then
					say("http://terraria.gamepedia.com/"..m:gsub(" ","_"))
				else
					say("No results.")
				end
			end
		end,
		["tell"]=function(dat)
			local m={}
			for ma in dat:gmatch("%S+") do
				m[#m+1]=ma
			end
			if not m[2] then
				say("Usage: .tell <person> <command> <args>")
				return
			end
			--[[if m[2]=="tell" or m[2]=="t" then
				say("Nice try :P")
			end]]
			if not cmds[m[2]] then
				say("Unknown command: "..m[2])
				return
			end
			pfx=m[1]..", "
			cmds[m[2]](m[3] or "")
			pfx=""
		end,
	}
	for k,v in pairs(short) do
		cmds[k]=cmds[v]
	end
	local spam={}
	function parsecmd(tb,dat)
		cmdat=tb
		local cmd=dat:match("^%S+")
		if cmds[cmd] then
			spam[tb.chan]=spam[tb.chan] or {}
			local sp=spam[tb.chan]
			sp[tb.host]=sp[tb.host] or 0
			if os.time()<sp[tb.host] then
				sv:send("NOTICE "..tb.nick.." :Please wait "..sp[tb.host]-os.time().." seconds before sending another command")
				if tb.chan==cnick then
					sv:send(".\r\n")
				else
					sv:send(" in "..tb.chan.."\r\n")
				end
				return
			end
			if tb.chan==cnick or cmd=="help" then
				sp[tb.host]=os.time()+5
			else
				sp[tb.host]=os.time()+30
			end
			cmds[cmd](dat:sub(#cmd+2))
		end
	end
end
local resp={
	["^PING (.+)"]=function(r)
		sv:send("PONG "..r.."\r\n")
	end,
	["^PING$"]=function()
		sv:send("PONG\r\n")
	end,
	["^:(.+) 433 (.+)"]=function()
		cnick=cnick.."_"
		sv:send("NICK "..cnick.."\r\n")
	end,
	[function() return "^:"..cnick.." MODE "..cnick.." :%+ix" end]=function()
		print("joined")
		if cnick~=config.nick then
			sv:send("PRIVMSG NickServ :identify "..config.nsuser.."\r\n")
		else
			sv:send("JOIN "..config.chan.."\r\n")
		end
	end,
	["^:NickServ!NickServ@services%. NOTICE (.-) :(.+)"]=function(ch,msg)
		if msg:sub(1,22)=="You are now identified" then
			sv:send("PRIVMSG NickServ :ghost "..config.nick.."\r\n")
		elseif msg=="\2"..config.nick.."\2 has been ghosted." then
			cnick=config.nick
			sv:send("NICK "..config.nick.."\r\nJOIN "..config.chan.."\r\n")
		end
	end,
	["^:(.-)!(.-) PRIVMSG (.-) :(.+)"]=function(ni,hn,ch,msg)
		local m=msg:match("^\1(.+)\1$")
		if m and ch==cnick then
			if m:sub(1,7)=="ACTION " then
				print("["..ch.."] * "..ni.." "..m:sub(8))
			else
				print("-CTCP- <"..ni.."> "..m)
			end
			if m=="VERSION" then
				sv:send("NOTICE "..ni.." :Potato v49.51.51.55\r\n")
			elseif m:sub(1,5)=="PING " or m=="PING" then
				sv:send("NOTICE "..ni.." :PONG"..m:sub(5).."\r\n")
			end
		else
			if m then
				if m:sub(1,7)=="ACTION " then
					print("["..ch.."] * "..ni.." "..m:sub(8))
				else
					print("["..ch.."] <"..ni.."> "..msg)
				end
			else
				print("["..ch.."] <"..ni.."> "..msg)
			end
			if ch==cnick then
				parsecmd({chan=ch,nick=ni,host=hn},msg)
			elseif msg:sub(1,1)=="." then
				parsecmd({chan=ch,nick=ni,host=hn},msg:sub(2))
			end
		end
	end,
	["^:NickServ!NickServ@services%. KILL "..config.nick.." (.+)"]=function()
		os.exit()
	end
}
local e,r=pcall(function()
	connect()
	while true do
		local s,e=sv:receive()
		if e=="closed" then
			connect()
		end
		while s do
			print(s)
			for k,v in pairs(resp) do
				if type(k)=="function" then
					k=k()
				end
				local m={s:match(k)}
				if m[1] then
					v(unpack(m))
				end
			end
			s,e=sv:receive()
			if e=="closed" then
				connect()
			end
		end
		socket.select({sv})
	end
end)
if not e then
	sv:send("QUIT "..r.."\r\n")
	error(r)
end
-- because im a potato
