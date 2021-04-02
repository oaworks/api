
P.scripts.testoab = () ->
  from = @params.from ? 0
  size = @params.size ? 100
  q = @params.q ? '*'
  finds = await @fetch 'https://api.cottagelabs.com/service/oab/finds?q=' + q + '&sort=createdAt:desc&from=' + from + '&size=' + size
  results = {checked: 0, errors: 0, matched: 0, dois: 0, nodoi: 0, titles: 0, permissions: {present: 0, matched: 0}, ill: {present: 0, matched: 0}, unmatched: {}}
  for r in finds?.hits?.hits ? []
    results.checked += 1
    try
      match = {}
      rec = r._source
      if typeof rec.input is 'string'
        if rec.input.indexOf(':') isnt -1
          [k, v] = rec.input = rec.input.split(',')[0].trim().split ':'
          k = k.trim()
          v = v.trim().replace /\"/g, ''
          match[k] = v
      if JSON.stringify(match) isnt '{}'
        if rec.plugin in ['shareyourpaper', 'instantill']
          match.plugin = rec.plugin
          match.from = rec.from if rec.from?
          match.config = rec.config if rec.config?
        res = await @svc.oaworks.find match
        res.url = res.url.split('?')[0] if res.url
        rec.url = rec.url.split('?')[0] if rec.url
        results.dois += 1 if res.metadata.doi is rec.metadata.doi
        results.nodoi += 1 if not rec.metadata.doi
        results.titles += 1 if res.metadata.title is rec.metadata.title
        if res.url is rec.url
          results.matched += 1
        else
          results.unmatched[rec.input] = {new: res.url, old: rec.url}
        if rec.permissions?
          results.permissions.present += 1
          if res.permissions?.best_permission? and rec.permissions?.best_permission?
            res.permissions.best_permission.issuer.id = res.permissions.best_permission.issuer.id.join(',') if Array.isArray res.permissions.best_permission?.issuer?.id
            rec.permissions.best_permission.issuer.id = rec.permissions.best_permission.issuer.id.join(',') if Array.isArray rec.permissions.best_permission?.issuer?.id
            if res.permissions.best_permission?.issuer?.id is rec.permissions.best_permission?.issuer?.id
              results.permissions.matched += 1
        if rec.ill?.subscription?
          results.ill.present += 1
          if res.ill?.subscription?.found is rec.ill.subscription.found
            results.ill.matched += 1
    catch
      results.errors += 1

  @mail msg: results
  return results

P.scripts.testoab._cache = false