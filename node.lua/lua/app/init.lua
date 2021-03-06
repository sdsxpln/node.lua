--[[

Copyright 2016 The Node.lua Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

local meta = {}
meta.name        = "lnode/app"
meta.version     = "1.0.0"
meta.license     = "Apache 2"
meta.description = "Application module for lnode"
meta.tags        = { "lnode", "app" }

local core   	= require('core')
local fs     	= require('fs')
local json   	= require('json')
local path   	= require('path')
local utils     = require('util')
local conf      = require('app/conf')
local ext   	= require('app/utils')

local exports = { meta = meta }

-------------------------------------------------------------------------------
-- misc

local getSystemInformation

local function getRootPath()
	return conf.rootPath
end

local function getAppPath()
	local rootPath = getRootPath()
	local appPath = path.join(rootPath, "app")
	if (not fs.existsSync(appPath)) then
		appPath = path.join(path.dirname(rootPath), "app")
	end

	return appPath

end

local function getRootURL()
	if (exports.rootURL) then
		return exports.rootURL
	end

	local systemInformation = getSystemInformation()
	if (systemInformation and systemInformation.registry) then
		local registry = systemInformation.registry
		if (registry) and (registry.url) then
			exports.rootURL = registry.url
		end

	else
		-- exports.rootURL = "http://node.sae-sz.com"
	end

	return exports.rootURL
end

local function getApplicationInfo(basePath)
	local filename = path.join(basePath, "package.json")
	local data = fs.readFileSync(filename)
	return data and json.parse(data)
end

-- 通过 cmdline 解析出相关的应用的名称
local function getApplicationName(cmdline)
	if (type(cmdline) ~= 'string') then
		return
	end

    local _, _, appName = cmdline:find('/([%w]+)/init.lua')

    if (not appName) then
        _, _, appName = cmdline:find('/lpm%S([%w]+)%Sstart')
    end

    if (not appName) then
        _, _, appName = cmdline:find('/lpm%Sstart%S([%w]+)')
    end    

    return appName
end

function getSystemInformation()
	if (exports.systemInformation) then
		return exports.systemInformation
	end

    local filename = getRootPath() .. '/package.json'
    exports.systemInformation = json.parse(fs.readFileSync(filename)) or {}
    return exports.systemInformation
end

local function executeApplication(basePath, ...)
	local filename = path.join(basePath, "init.lua")
	if (not fs.existsSync(filename)) then
		return -3, '"' .. basePath .. '/init.lua" not exists!'
	end

    --console.log(package.path)

	local script, err = loadfile(filename)
	if (err) then
		error(err)
		return -4, err
	end

	_G.arg = table.pack(...)
	return 0, script(...)
end

-- 显示错误信息
local function printError(errorInfo, ...)
	print('Error:', console.color("err"), tostring(errorInfo), console.color(), ...)

end

-------------------------------------------------------------------------------
-- exports

exports.meta  = {}
setmetatable(exports, exports.meta)

--
exports.rootPath 		= getRootPath()
exports.rootURL 		= getRootURL()

--
exports.formatFloat 	= ext.formatFloat
exports.formatBytes 	= ext.formatBytes
exports.table 			= ext.table

-------------------------------------------------------------------------------
-- profile

local loadProfile = function()
    if (exports._profile) then
        return exports._profile
    end

	exports._profile = conf(exports.appName())
    return exports._profile
end

function exports.appName()
	return exports.name or 'user'
end

-- 启用/禁用指定的应用后台进程
function exports.enable(newNames, enable)
    local names, count, oldData = exports.getStartNames()

    for _, name in ipairs(newNames) do
        if (enable) then
            local filename = path.join(exports.rootPath, 'app', name)
            if (fs.existsSync(filename)) then
                names[name] = name
            end

        else
            names[name] = nil
        end
    end
    
    -- save to file
    local list = {}
    for _, item in pairs(names) do
        list[#list + 1] = item
    end

    table.sort(list, function(a, b)
        return tostring(a) < tostring(b)
    end)

    list[#list + 1] = ''
    local fileData = table.concat(list, "\n")   
    if (oldData == fileData) then
        return fileData
    end

    print("Updating process list...")
    print("  " .. table.concat(list, " ") .. "\n")

    local filename = exports.getStartFilename()

    local tempname = filename .. ".tmp"
    local ret, err = fs.writeFileSync(tempname, fileData)
    if (err) then 
    	console.log(err)
    	return
    end

    os.remove(filename)
    os.rename(tempname, filename)

    return fileData
end

-- 配置文件名
function exports.getStartFilename()
	return path.join(exports.rootPath, 'conf', 'start.conf')
end

-- 返回所有需要后台运行的应用
function exports.getStartNames()
    local filedata = fs.readFileSync(exports.getStartFilename())
    local names = {}
    local count = 0

    if (not filedata) then
        return names, count, filedata
    end

    local list = filedata:split("\n")
    for _, item in ipairs(list) do
        if (#item > 0) then
            local filename = path.join(exports.rootPath, 'app', item)
            if fs.existsSync(filename) then
                names[item] = item
                count = count + 1
            end
        end
    end
    
    return names, count, filedata
end

-- 删除指定名称的配置参数项的值
-- @param key {String}
function exports.unset(key)
    if (not key) then
        return
    end

	local profile = loadProfile()
	if (profile) and (profile:get(key)) then
		profile:set(key, nil)
		profile:commit()
	end
end

-- 打印指定名称的配置参数项的值
-- @param key {String}
function exports.get(key)
	if (not key) then
        return
    end

	local profile = loadProfile()
    if (profile) then
		return profile:get(key)
	end
end

-- 设置指定名称的配置参数项的值
-- @param key {String|Object}
-- @param value {String|Number|Boolean}
function exports.set(key, value)
	if (not key) then
		return
	end

	local profile = loadProfile()
    if (not profile) then
        return
    end

    if (type(key) == 'table') then
        local count = 0
        for k, v in pairs(key) do
            local oldValue = profile:get(k)
            --print(k, v, oldValue)

            if (not oldValue) or (v ~= oldValue) then
                profile:set(k, v)

                count = count + 1
            end
        end

        if (count > 0) then
            profile:commit()
        end

    else 
    	if (not key) or (not value) then
            return
        end

        local oldValue = profile:get(key)
        if (not oldValue) or (value ~= oldValue) then
            profile:set(key, value)
            profile:commit()
        end
    end
end

-------------------------------------------------------------------------------
-- methods

-- 以后台的方式运行指定的应用
function exports.daemon(name)
	if (not name) or (name == '') then
        print("Error: missing required argument '<name>'.")
		return -1
	end

	local filename = path.join(getAppPath(), name, 'init.lua')
	if (not fs.existsSync(filename)) then
		print('"' .. filename .. '" not exists!')
		return -3
	end

    local cmdline  = "lnode -d " .. filename .. " start"
    --local cmdline  = "lpm " .. name .. " start &"
	print('start and daemonize: ' .. name)
	os.execute(cmdline)
end

-- 关闭指定的进程, 并从进程列表中删除
function exports.delete(name)
    return exports.stop(name)
end

-- 
function exports.execute(name, ...)
	local basePath
	if (not name) then
		basePath = process.cwd()
	else
		basePath = path.join(getAppPath(), name)
	end

	return executeApplication(basePath, ...)
end

-- 
function exports.info(name)
	local filename = path.join(getAppPath(), name)
	return getApplicationInfo(filename)
end

-- kill 指定名称的进程
function exports.kill(name)
    if (not name) then
        print('missing required argument `name`!\n')
    end

    local list = exports.processes()
    if (not list) or (#list < 1) then
        return
    end

    local uv = require('uv')
    local tmpdir = os.tmpdir or '/tmp'

    if (name == 'all') then
        local ppid = process.pid
        for _, proc in ipairs(list) do
            if (ppid ~= proc.pid) then
                print('kill: ' .. proc.name .. '(' .. proc.pid .. ')')
                uv.kill(proc.pid, "sigterm")
                
                os.remove(path.join(tmpdir, proc.name .. '.lock'))
            end
        end

    else
        for _, proc in ipairs(list) do
            if (proc.name == name) then
                local cmd = "kill " .. proc.pid
                print("kill (" .. name .. ") " .. proc.pid)
                uv.kill(proc.pid, "sigterm")
            end
        end

        os.remove(path.join(tmpdir, name .. '.lock'))
    end
end

-- 返回包含所有安装的应用的列表
function exports.list()
	local appPath = getAppPath()
	local list = {}

	local files = fs.readdirSync(appPath)
	if (not files) then
		return list
	end

	for i = 1, #files do
		local file 		= files[i]
		local filename  = path.join(appPath, file)
		local name 		= path.basename(file)
		local info 		= getApplicationInfo(filename)
		if (info) then
			info.name = info.name or name
			list[#list + 1] = info
		end
	end

	return list
end

function exports.main(handler, action, ...)
    local method = handler[action]
    if (not method) then
        method = handler.help
    end

    if (not exports.name) then
    	exports.name = getApplicationName(utils.filename(4))
    end

    if (method) then
        method(...)
	end
end

-- 打印所有安装的应用
function exports.printList()
	local appPath = path.join(getAppPath())

	local apps = exports.list()
	if (not apps) or (#apps <= 0) then
		print("No applications are installed yet.", appPath)
		return
	end

	local grid = ext.table({ 12, 12, 48 })
	grid.line()
	grid.cell('Name', 'Version', 'Description')
	grid.line('=')

	for _, app in ipairs(apps) do
		grid.cell(app.name, app.version, app.description)
	end

	grid.line()
    print(string.format("+ total %s applications (%s).", 
        #apps, appPath))
end

-- 通过 cmdline 解析出相关的应用的名称
function exports.parseName(cmdline)
    local _, _, appName = cmdline:find('lnode.+/([%w]+)/init.lua')

    if (not appName) then
        _, _, appName = cmdline:find('lnode.+/lpm%s([%w]+)%sstart')
    end

    if (not appName) then
        _, _, appName = cmdline:find('lnode.+/lpm%sstart%s([%w]+)')
    end    

    return appName
end

-- 返回包含所有正在运行中的应用进程信息的数组
-- @return {Array} 返回 [{ name = '...', pid = ... }, ... ]
function exports.processes()
    local list = {}
    local count = 0

    local files = fs.readdirSync('/proc') or {}
    if (not files) or (#files <= 0) then
        print('This command only support Linux!')
        return
    end

    local execPath = process.execPath
    --console.log(exepath)

    for _, file in ipairs(files) do
        local pid = tonumber(file)
        if (not pid) then
            goto continue
        end

        local filename = path.join('/proc', file, 'exe')
        local pathname = fs.readlinkSync(filename)
        if (not pathname) then
            --
            
        elseif (pathname ~= execPath) then
            goto continue
        end

        local filename = path.join('/proc', file, 'cmdline')
        if not fs.existsSync(filename) then
            goto continue
        end
        local cmdline = fs.readFileSync(filename) or ''
        --console.log(cmdline)
        --console.log(pathname)

        local name = exports.parseName(cmdline)
        if (not name) then
            goto continue
        end

        table.insert(list, {name = name, pid = pid})
        count = count + 1

        ::continue::
    end

    return list, count
end

-- 打印所有正在运行中的进程
function exports.printProcesses(...)
    local list  = exports.processes()
    if (not list) or (#list < 1) then
        print('No matching application process were found!')
        return
    end

    --console.log(names, list)

    local services = {}

    for _, proc in ipairs(list) do
        local service = services[proc.name]
        if (not service) then
            service = { name = proc.name }
            services[proc.name] = service
        end

        if (not service.pids) then
            service.pids = {}
        end

        service.pids[#service.pids + 1] = tostring(proc.pid)
    end

    list = {}
    for name, service in pairs(services) do
        if (name ~= '') then
            list[#list + 1] = service
        end
    end 

    table.sort(list, function(a, b) 
        return tostring(a.name) < tostring(b.name) 
    end) 

    local grid = exports.table({ 10, 16 })
    grid.line()
    grid.cell("name", "pid")
    grid.line()
    for _, proc in ipairs(list) do
        local pids = proc.pids or {}
        grid.cell(proc.name, table.concat(pids, ","))
    end
    grid.line()
end


-- 重启指定的名称的应用程序
function exports.restart(name, ...)
    if (not name) then
        print('missing required argument `name`!\n')

    elseif (name == 'all') then
        print('Restarting all applications...')
        exports.kill('all')
        exports.start('all')

    else
        local list = table.pack(name, ...)
        for _, name in ipairs(list) do
            print('Restarting ' .. name .. '...')
        end

        exports.kill(name, ...)
        exports.start(name, ...)
        print("done")
    end
end

-- Start and deamonize specified application
function exports.start(name, ...)
    if (not name) then
        print('missing required argument `name`!\n')

    elseif (name == 'all') then
        local names = exports.getStartNames()
        for _, name in pairs(names) do
            exports.daemon(name)
        end

    else
        local list = table.pack(name, ...)
        exports.enable(list, true)

        for _, name in ipairs(list) do
            exports.daemon(name)
        end    
    end
end

-- 杀掉指定名称的进程，并阻止其在后台继续运行
function exports.stop(name, ...)
    if (not name) then
        print('missing required argument `name`!\n')

    elseif (name == 'all') then
        exports.kill('all')
    
    else
        local list = table.pack(name, ...)
        exports.enable(list, false)

        for _, app in ipairs(list) do
            exports.kill(app)   
        end

        print("done.")
    end
end

-- 返回当前系统目标平台名称, 一般是开发板的型号或 PC 操作系统的名称
-- 因为不同平台的可执行二进制文件格式是不一样的, 所有必须严格匹配
function exports.target()
	return ext.getSystemTarget()
end

-- 创建文件锁, 防止同时运行多个进程
function exports.tryLock(name)
    name = name or exports.name

    local tmpdir = os.tmpdir or '/tmp'
    local lockname = path.join(tmpdir, name .. '.lock')
    local lockfd = fs.openSync(lockname, 'w+')
    if (not lockfd) then
        return
    end

    local ret = fs.fileLock(lockfd, 'w')
    if (ret == -1) then
        fs.closeSync(lockfd)
        return
    end

    process:on("exit", function()
        fs.fileLock(lockfd, 'u')
        os.remove(lockname)
    end)

    return lockfd
end

-- 释放文件锁
function exports.unlock(lockfd)
    fs.fileLock(lockfd, 'u')
end

-- 解析 exports 的 package.json 文件, 并显示相关的使用说明信息. 
function exports.usage(dirname)
    local fs    = require('fs')
    local json  = require('json')

    local data      = fs.readFileSync(dirname .. '/package.json')
    local package   = json.parse(data) or {}

    local color  = console.color
	local quotes = color('quotes')
	local desc 	 = color('braces')
	local normal = color()

    -- Name
    print(quotes, '\nusage: lpm ' .. tostring(package.name) .. ' <command> [args]\n', normal)

    -- Description
    if (package.description) then
        print(package.description, '\n')
    end

	local printList = function(name, list)
		if (not list) then
			return
		end

        print(name .. ':\n')
		for _, item in ipairs(list) do
			print('- ' ..  string.padRight(item.name, 24), 
				desc .. tostring(item.desc), normal)
		end

		print('')
	end

    printList('Settings', 			package.settings)
    printList('IPC command', 		package.rpc)
    printList('available command', 	package.commands)
end

exports.meta.__call = function(self, handler)
    exports.main(handler, table.unpack(arg))
end

return exports
