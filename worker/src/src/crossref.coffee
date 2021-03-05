
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

_xref_hdr = {'User-Agent': S.name + '; mailto:' + S.mail?.to}

P.src.crossref = {}

P.src.crossref.journals = (issn) ->
  # by being an index, should default to a search of the index, then run this query if not present, which should get saved to the index
  issn ?= this?.params?.journals ? this?.params?.issn
  #url = 'https://api.crossref.org/journals?query=' + issn
  url = 'https://dev.lvatn.com/use/crossref/journals/' + issn
  res = await @fetch url #, {headers: _xref_hdr} # TODO check how headers get sent by fetch
  #return if res?.message?['total-results']? and res.message['total-results'].length then res.message['total-results'][0] else undefined
  return if res?.ISSN? then res else undefined

P.src.crossref.journals._index = true
P.src.crossref.journals._key = 'ISSN'

P.src.crossref.works = (doi) ->
  if this?.params?.title or (typeof doi is 'object' and doi.title?) or (typeof doi is 'string' and doi.indexOf('10.') isnt 0)
    res = @src.crossref.works._title if this?.params?.title then @params.title else if typeof doi is 'object' then doi.title else doi
  else
    # a search of an index of works - and remainder of route is a DOI to return one record
    doi ?= this?.params?.works ? this?.params?.doi
    if typeof doi is 'string'
      doi = doi.split('://')[1] if doi.indexOf('http') is 0
      doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
  
      # for now just get from old system instead of crossref
      #url = 'https://api.crossref.org/works/' + doi
      url = 'https://dev.lvatn.com/use/crossref/works/' + doi
      res = await @fetch url #, {headers: _xref_hdr}

  if res?.DOI? #res?.message?.DOI?
    rec = res #res.data.message
    delete rec.relation
    delete rec.reference # is there anything worth doing with these? In some cases they are extremely long, enough to cause problems in the index
    delete rec.abstract
    #if typeof rec.abstract is 'string' and this?.convert?.html2txt?
    #  rec.abstract = @convert.html2txt rec.abstract
    return rec
  else
    return undefined

P.src.crossref.works._kv = false
P.src.crossref.works._index = settings: number_of_shards: 9
P.src.crossref.works._key = 'DOI'

P.src.crossref.works._title = (title) ->
  title ?= @params.title
  return undefined if typeof title isnt 'string'
  
  qr = 'title.exact:"' + title + '"'
  if title.indexOf(' ') isnt -1
    qr += ' OR ('
    f = true
    for t in title.split ' '
      if t.length > 2
        if f is true
          f = false
        else
          qr += ' AND '
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")'
    qr += ')'

  url = 'https://dev.lvatn.com/use/crossref/works?q=' + qr
  res = await @fetch url
  #res = @src.crossref.works qr

  possible = false
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
  for r in res?.hits?.hits ? []
    rec = r._source
    rt = (if typeof rec.title is 'string' then rec.title else rec.title[0]).toLowerCase()
    if rec.subtitle?
      st = (if typeof rec.subtitle is 'string' then rec.subtitle else rec.subtitle[0]).toLowerCase()
      rt += ' ' + st if typeof st is 'string' and st.length and st not in rt
    rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
    if (ltitle.indexOf(rt) isnt -1 or rt.indexOf(ltitle) isnt -1) and ltitle.length/rt.length > 0.7 and ltitle.length/rt.length < 1.3
      matches = true
      for k of metadata
        if k not in ['citation','title'] and typeof metadata[k] in ['string','number']
          matches = not fr[k]? or typeof fr[k] not in ['string','number'] or fr[k].toLowerCase() is metadata[k].toLowerCase()
      if matches
        if rec.type is 'journal-article'
          return if format then API.use.crossref.works.format(rec) else rec
        else if possible is false or possible.type isnt 'journal-article' and rec.type is 'journal-article'
          possible = rec

  return if possible is false then undefined else possible


# and need the code that builds the index and keeps it up to date
# and someting to trigger a load each day for example
# probably requires a cron schedule to read some kind of setting or KV of last-updated indexes, and their update schedule
# doing the regular index update will probably be a long-running job, so needs to be triggered but run on the backend machine
