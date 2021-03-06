local kong_cache = require "kong.cache"
local kong_cluster_events = require "kong.cluster_events"
local Factory = require "kong.dao.factory"
local helpers = require "spec.helpers"
local worker_events = require "resty.worker.events"
local create_unique_key = require("kong.tools.utils").uuid


local HARD_ERROR = { err = "hard:" .. create_unique_key() }
local SOFT_ERROR = { err = "soft:" .. create_unique_key() }


local cb_call_count


local function load_into_memory(value_to_return)
  cb_call_count = cb_call_count + 1
  if value_to_return == HARD_ERROR then
    return error(value_to_return.err)
  elseif value_to_return == SOFT_ERROR then
    return nil, value_to_return.err
  else
    return value_to_return
  end
end


describe("dao in-memory cache", function()

  local cache, key

  setup(function()
    assert(worker_events.configure {
      shm = "kong_process_events",
    })
    local dao_factory = assert(Factory.new(helpers.test_conf))
    local cluster_events = assert(kong_cluster_events.new {
      dao = dao_factory,
    })
    cache = kong_cache.new {
      cluster_events = cluster_events,
      worker_events = worker_events,
    }
  end)

  before_each(function()
    cb_call_count = 0
    key = create_unique_key()
  end)


  it("handles soft callback errors", function()
    for _ = 1, 2 do
      local value, err = cache:get(key, nil, load_into_memory, SOFT_ERROR)
      assert.is_nil(value)
      assert.matches(SOFT_ERROR.err, err, nil, true)
    end
    assert.equals(2, cb_call_count)
  end)


  it("handles hard callback errors", function()
    for _ = 1, 2 do
      local value, err = cache:get(key, nil, load_into_memory, HARD_ERROR)
      assert.is_nil(value)
      assert.matches(HARD_ERROR.err, err, nil, true)
    end
    assert.equals(2, cb_call_count)
  end)


  it("ensure callbacks do not increase memory (regression test for #3277)", function()
    local counts = {}
    for i, n in ipairs({ 2000, 2000, 2000 }) do
      for _ = 1, n do
        local wrapped = function(...) return load_into_memory(...) end
        local value, err = cache:get(key, nil, wrapped, SOFT_ERROR)
        assert.is_nil(value)
        assert.matches(SOFT_ERROR.err, err, nil, true)
      end
      collectgarbage()
      collectgarbage()
      counts[i] = collectgarbage("count")
    end
    -- No significant difference between runs
    assert.truthy(math.abs(counts[1] - counts[2]) < 10)
    assert.truthy(math.abs(counts[2] - counts[3]) < 10)
    assert.truthy(math.abs(counts[1] - counts[3]) < 10)
  end)


  it("handles nil as return value", function()
    for _ = 1, 2 do
      local value, err = cache:get(key, nil, load_into_memory, nil)
      assert.is_nil(value)
      assert.is_nil(err)
    end
    assert.equals(1, cb_call_count)
  end)

end)
