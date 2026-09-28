local function getBoundingBox(min, max)
    local pad = 0.001

    local box = {
        vector3(min.x - pad, min.y - pad, min.z - pad),
        vector3(max.x + pad, min.y - pad, min.z - pad),
        vector3(max.x + pad, max.y + pad, min.z - pad),
        vector3(min.x - pad, max.y + pad, min.z - pad),

        vector3(min.x - pad, min.y - pad, max.z + pad),
        vector3(max.x + pad, min.y - pad, max.z + pad),
        vector3(max.x + pad, max.y + pad, max.z + pad),
        vector3(min.x - pad, max.y + pad, max.z + pad)
    }

    return box
end

local function getBoundingBoxPolyMatrix(box)
    local polys = {
        { box[3], box[2], box[1] },
        { box[4], box[3], box[1] },

        { box[5], box[6], box[7] },
        { box[5], box[7], box[8] },

        { box[3], box[4], box[7] },
        { box[8], box[7], box[4] },

        { box[1], box[2], box[5] },
        { box[6], box[5], box[2] },

        { box[2], box[3], box[6] },
        { box[3], box[7], box[6] },

        { box[5], box[8], box[4] },
        { box[5], box[4], box[1] }
    }

    return polys
end

local function drawPolyMatrix(polys)
    for i, poly in ipairs(polys) do
        local x1 = poly[1].x
        local y1 = poly[1].y
        local z1 = poly[1].z

        local x2 = poly[2].x
        local y2 = poly[2].y
        local z2 = poly[2].z

        local x3 = poly[3].x
        local y3 = poly[3].y
        local z3 = poly[3].z

        DrawPoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, 0, 0, 255, 200)
    end
end

local function drawBox(min, max)
    local box = getBoundingBox(min, max)
    local polys = getBoundingBoxPolyMatrix(box)
    drawPolyMatrix(polys)
end

---@param entity integer
exports('drawEntityBox', function(entity)
    if not DoesEntityExist(entity) then
        return
    end

    local min, max = GetModelDimensions(GetEntityModel(entity))

    local minWorld = GetOffsetFromEntityInWorldCoords(entity, min.x, min.y, min.z)
    local maxWorld = GetOffsetFromEntityInWorldCoords(entity, max.x, max.y, max.z)
    drawBox(minWorld, maxWorld)
end)

exports('drawBox', drawBox)