
P.test = (sid, max) ->
  row = @params.row ? @params.id
  group = @params.test ? @params.group
  max ?= @params.max ? (if row then 1 else 10000)
  res = summary: {ran: 0, max: max, id: row, responded: 0, errors: 0, differences: 0, difference: (@params.diff ? @params.difference ? true), anomalous: 0}, anomalies: {}, anomalous_ids: [], errors: [], differences: {} #, specs: {}
  res.sheet = id: sid ? @params.sheet ? '1GQhgRCZ9ovfTN_wwKCvoAqf9QlO7ozcxScBgjEnpfl8/tests'
  # https://docs.google.com/spreadsheets/d/1GQhgRCZ9ovfTN_wwKCvoAqf9QlO7ozcxScBgjEnpfl8
  res.sheet.url ?= 'https://docs.google.com/spreadsheets/d/' + res.sheet.id.split('/')[0]
  res.sheet.content = await @src.google.sheets res.sheet.id
  res.responses = []
  res.diffs = []
  #traversed = 1 # first row will be column names, so the sheet user would start counting rows from 2
  console.log res.sheet.content.length, 'tests found to run in', res.sheet.id
  for t in res.sheet.content
    #traversed += 1
    break if res.summary.ran is max
    t.PARAMS = t.QUERY if not t.PARAMS? and t.QUERY?
    t.ENDPOINT = t.ENDPOINT_PRIMARY if not t.ENDPOINT? and t.ENDPOINT_PRIMARY?
    t.DIFF = t.ENDPOINT_SECONDARY if not t.DIFF? and t.ENDPOINT_SECONDARY?
    #if t.ENDPOINT and (not row? or traversed is row)
    if t.ENDPOINT and t.ID and (not row? or t.ID.toString().toLowerCase() is row.toString().toLowerCase()) and (not group or group.toString().toLowerCase() in t.GROUP.toString().toLowerCase().replace(/ /g, '').split(';'))
      try t.PARAMS = t.PARAMS.trim() # clean it?
      #t.ignore ?= []
      #t.ignore = t.ignore.split() if typeof t.ignore is 'string'
      res.summary.ran++
      anoname = (t.ID ? t.NAME ? t.ENDPOINT ? '') + (if not t.ID and not t.NAME and t.PARAMS then '(' + t.PARAMS + ')' else '')
      anoname = 'UNIDENTIFIED_TEST_' + res.summary.ran if anoname is ''
      try
        # handle if params are a URL extension such as /blah and possibly inline params, or a string, 
        # or comma separated strings, or JSON object/list. Note also this must still be a string representation 
        # for the results object below. It may also be empty, in which case what will uniquely identify the result?
        if t.ENDPOINT.startsWith 'http'
          resp = await @fetch t.ENDPOINT + (if not t.ENDPOINT.endsWith('/') and not (t.PARAMS ? '').startsWith('/') then '/' else '') + (t.PARAMS ? '')
        else
          resp = await @[t.ENDPOINT] t.PARAMS
        res.summary.responded++
        for c of t
          if c not in ['ID', 'GROUP', 'ENDPOINT', 'ENDPOINT_PRIMARY', 'ENDPOINT_SECONDARY', 'DIFF', 'PARAMS', 'QUERY', 'NAME', 'SPEC', 'TEST_LINK', 'PRIMARY_URL', 'GROUP_MANUAL', 'ID_MANUAL', 'TEST_REQUIREMENTS_MET', ''] and not c.startsWith('OPTIONS.')
            expect = t[c]
            if expect? and expect isnt ''
              part = await @dot resp, c
              gt = false
              lt = false
              nt = false
              #console.log res.summary.ran, c, part, expect, t[c]
              contains = typeof expect is 'string' and (expect.startsWith('~') or (Array.isArray(part) and (not expect.includes(',') or part.length isnt expect.split(',').length))) # this is for checking if a list contains
              if typeof part is 'object'
                if not contains
                  expect = expect.split(',') if typeof expect is 'string' and Array.isArray part
                  part = JSON.stringify part
                  expect = JSON.stringify(expect) if typeof expect is 'object'
              else
                try
                  n = parseFloat part # what about dates?
                  if typeof n is 'number' and n.toString().trim().length is part.toString().trim().length and not isNaN n
                    part = n
                    if expect.startsWith '>'
                      gt = true
                      expect = parseFloat expect.slice 1
                    else if expect.startsWith '<'
                      lt = true
                      expect = parseFloat expect.slice 1
                    else if expect.startsWith '!'
                      nt = true
                      expect = parseFloat expect.slice 1
                    else
                      expect = parseFloat expect
              if typeof expect is 'boolean' or typeof part is 'boolean'
                try
                  expect = expect.toString().trim().toLowerCase()
                  part = part.toString().trim().toLowerCase()
              nothing = expect in ['!*', 'UNDEFINED', 'NULL', 'NONE']
              anything = expect is '*'
              includes = not anything and not nothing and typeof expect is 'string' and (expect.startsWith('*') or expect.endsWith('*'))
              starts = includes and not expect.startsWith '*'
              ends = includes and not expect.endsWith '*'
              expect = expect.replace(/\*/g, '') if includes
              contains = false if nothing
              if not nt and typeof expect is 'string' and expect.startsWith('!') and expect.length > 1
                nt = true
                expect = expect.slice 1
              if contains
                expect = expect.slice(1) if typeof expect is 'string' and expect.startsWith '~'
                contained = anything or expect in part or parseFloat(expect) in part or parseInt(expect) in part or (expect.toLowerCase() is 'true' and true in part) or (expect.toLowerCase() is 'false' and false in part)
              console.log res.summary.ran, c, 'part:', typeof part, part, 'expect:', typeof expect, expect, typeof t[c], t[c], 'gt:', gt, 'lt:', lt, 'nt:', nt, 'nothing:', nothing, 'anything:', anything, 'includes:', includes, 'starts:', starts, 'ends:', ends, 'contains:', contains, 'contained:', contained
              #if (not part? and not nothing) or (part? and JSON.stringify(part) not in ['[]', '{}'] and nothing) or (contains and not contained) or (starts and not part.startsWith expect) or (ends and not part.endsWith expect) or (not starts and not ends and includes and not part.includes expect) or (nt and part is expect) or (gt and part <= expect) or (lt and part >= expect) or (not gt and not lt and not nt and not anything and not nothing and not contains and not includes and part isnt expect)
              if (not part? and not nothing and not nt) or (part? and JSON.stringify(part) not in ['[]', '{}'] and nothing) or (contains and not contained and not nt) or (starts and not part.startsWith expect) or (ends and not part.endsWith expect) or (not starts and not ends and includes and not part.includes expect) or (nt and (part is expect or (contains and contained))) or (gt and part <= expect) or (lt and part >= expect) or (not gt and not lt and not nt and not anything and not nothing and not contains and not includes and part isnt expect)
                if not res.anomalies[anoname]?
                  res.anomalous_ids.push anoname
                  res.summary.anomalous++
                  res.anomalies[anoname] = {}
                res.anomalies[anoname][c] = group: t.GROUP, expected: t[c], reported: (if not part? then 'UNDEFINED' else part)
        res.responses.push resp
        if t.DIFF and res.summary.difference is true
          try
            if t.DIFF.startsWith('http')
              resd = await @fetch t.DIFF + (if not t.DIFF.endsWith('/') and not (t.PARAMS ? '').startsWith('/') then '/' else '') + (t.PARAMS ? '')
            else
              resd = await @[t.DIFF] t.PARAMS
            #diff = await @fetch 'https://s.leviathan.sh/diff?a=' + encodeURIComponent('https://bg.beta.oa.works/permissions/' + t.PARAMS) + '&b=' + encodeURIComponent('https://bg.beta.oa.works/permissions_new/' + t.PARAMS)
            diff = await @fetch 'https://s.leviathan.sh/diff', body: a: resp, b: resd
            res.diffs.push diff
            if diff.diff.length
              res.summary.differences += 1
              res.differences[anoname] = diff.diff
        '''if false #t.SPEC
          try
            specd = await @fetch 'https://s.leviathan.sh/diff/ie', body: a: resp, spec: t.SPEC
            res.specs[t.ENDPOINT + '_' + t.PARAMS] = specd.diffie'''
        await @sleep 200
      catch err
        console.log err
        res.errors.push anoname
        res.summary.errors++

  if not @params.verbose
    try res.differences[d] = res.differences[d].length for d of res.differences
    delete res[dl] for dl in ['responses', 'diffs']
    #try res.sheet.content = res.sheet.content.length
    delete res.sheet.content # for now this is not wanted as adding new tests changes the value and fails the test
  return res

P.tests = P.test
