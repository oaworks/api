
import { spawn } from 'child_process'

P._child = (cmd, args=[], input, path, limit=100) ->
  #try
  path = process.env.PWD + '/' if path is true
  path = process.env.PWD + '/' + path if typeof path is 'string' and not path.startsWith '/'
  path += '/' if typeof path is 'string' and not path.endsWith '/'
  args = [args] if not Array.isArray args
  sp = spawn (path ? '') + cmd, args
  res = ''
  done = false
  sp.stdout.on 'data', (data) -> res += data
  sp.stdout.on 'end', () -> done = true

  if input?
    sp.stdin.write JSON.stringify input
  sp.stdin.end()

  while not done
    await @sleep limit

  try res = JSON.parse res
  return res
  #catch
  #  return ''