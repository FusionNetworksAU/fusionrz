Core.databaseReady = false

local databaseReadyCallbacks = {}

function Core.onDatabaseReady(callback)
    if Core.databaseReady then
        return callback()
    end

    databaseReadyCallbacks[#databaseReadyCallbacks + 1] = callback
end

CreateThread(function()
    local parent = MySQL.single.await([[
        SELECT c.COLUMN_TYPE, c.COLUMN_KEY, t.ENGINE
        FROM information_schema.COLUMNS c
        JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE c.TABLE_SCHEMA = DATABASE() AND c.TABLE_NAME = 'users' AND c.COLUMN_NAME = 'userId'
    ]])

    local columnType = parent and parent.COLUMN_TYPE:gsub('%(%d+%)', '')

    if parent and (columnType ~= 'int unsigned' or parent.COLUMN_KEY == '' or parent.ENGINE ~= 'InnoDB') then
        error(('[core] users.userId must be INT UNSIGNED and indexed on an InnoDB table (found %s, key %s, engine %s)')
            :format(parent.COLUMN_TYPE, parent.COLUMN_KEY, parent.ENGINE))
    end

    local schema = LoadResourceFile(GetCurrentResourceName(), 'core.sql')

    if not schema then
        error('Unable to load core.sql')
    end

    for statement in schema:gmatch('(.-);%s*') do
        if statement:match('%S') then
            MySQL.query.await(statement)
        end
    end

    Core.databaseReady = true

    for index = 1, #databaseReadyCallbacks do
        databaseReadyCallbacks[index]()
    end

    table.wipe(databaseReadyCallbacks)

    print('[core] Database schema initialized')
end)