

P.src.microsoft.load = () ->
  keys =
    'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate']
    'abstract': ['PaperId', 'Abstract']
    'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
    'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate']

  infolder = '/mnt/volume_nyc3_01/mag/' # where the lines should be read from
  lastfile = '/mnt/volume_nyc3_01/mag/last' # prefix of where to record the ID of the last item read from the kind of file
  howmany = -1 # max number of lines to process. set to -1 to keep going
  batchsize = 20000 # how many records to batch upload at a time
  total = 0

  for kind in (if @params.kinds then @params.kinds.split(',') else @keys keys)
    batch = []
    kindlastfile = lastfile + '_' + kind
    kindtotal = 0
    last = false
    if not @refresh
      try last = (await fs.readFile kindlastfile).toString()
    waiting = last isnt false
    
    if last isnt 'DONE'
      await @src.microsoft.graph[kind]('') if @params._delete and last is false

      _lines = (path) =>
        readline.createInterface 
          input: fs.createReadStream path
          crlfDelay: Infinity
    
      for await line from _lines infolder + (if kind is 'relation' then 'PaperAuthorAffiliations.txt' else kind.substr(0,1).toUpperCase() + kind.substr(1) + 's.txt')
        break if howmany isnt -1 and total >= howmany
        vals = line.split '\t'
  
        if waiting
          waiting = false if vals[0] is last
        else
          total += 1
          kindtotal += 1
          kc = 0
          obj = {}
          if kind isnt 'relation'
            obj._id = vals[0]
            try obj._id.trim()
          if kind is 'abstract'
            obj.PaperId = vals[0]
            ind = JSON.parse vals[1]
            al = []
            al.push('') while al.length < ind.IndexLength
            for k in ind.InvertedIndex
              for p in ind.InvertedIndex[k]
                al[p] = k
            obj.Abstract = al.join ' '
          else
            for key in keys[kind]
              vs = vals[kc]
              try vs.trim()
              obj[key] = vs if vs
              kc += 1
          if kind is 'paper'
            if obj.JournalId
              try obj.journal = await @src.microsoft.graph.journal obj.JournalId
            try obj.abstract = await @src.microsoft.graph.abstract obj.PaperId
            try
              for await rr from @index._for 'src_microsoft_graph_relation', 'PaperId:"' + obj._id + '"'
                if rr.AuthorId and author = await @src.microsoft.graph.author rr.AuthorId
                  if author.LastKnownAffiliationId
                    try author.affiliation = await @src.microsoft.graph.affiliation author.LastKnownAffiliationId
                  obj.author ?= []
                  obj.author.push author

          batch.push obj
  
        if batch.length >= batchsize
          console.log total, kindtotal, vals[0]
          await @src.microsoft.graph[kind] batch
          await fs.writeFile kindlastfile, vals[0]
          batch = []
  
      if batch.length
        await @src.microsoft.graph[kind] batch
        batch = []
      await fs.writeFile kindlastfile, 'DONE'

  return total

P.src.microsoft.load._async = true
P.src.microsoft.load._auth = 'root'

