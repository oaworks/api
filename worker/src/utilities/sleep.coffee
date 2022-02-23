
P.sleep = (ms) -> # await this when calling it to actually wait
  try ms ?= @params.ms
  return new Promise (resolve) => setTimeout resolve, ms ? 1000
P.sleep._auth = 'root'

