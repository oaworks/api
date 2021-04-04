

# https://search.fatcat.wiki/fatcat_release_v03b/_search?q=doi:%2210.1007/s00276-005-0333-8%22
# that used to work, but they've moved the index now, and it doesn't seem to. Althought the main 
# ES base is still there - just can't get it to respond without finding the index name. 
# However, developments on querying the releases gives us a possible solution:

P.src.fatcat = (doi) ->
  doi ?= @params.fatcat ? @params.doi
  try
    res = await @fetch 'https://api.fatcat.wiki/v0/release/lookup?expand=files&hide=abstracts,refs&doi=' + doi
    return res
  catch
    return undefined

# is there also a title search? Or only IDs? title= doesn't work. Can explore more later.

# we could index this as we get them if that turns out to be useful
# to begin with, normal caching should be sufficient.

''' for example:
 10.1088/0264-9381/19/7/380
 has a files section, containing:
 [
    {
      "release_ids":["3j36alui7fcwncbc4xdaklywb4"],
      "mimetype":"application/pdf",
      "urls":[
        {"url":"http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"web"},
        {"url":"https://web.archive.org/web/20091024040004/http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"webarchive"},
        {"url":"https://web.archive.org/web/20040827040202/http://www.gravity.uwa.edu.au:80/amaldi/papers/Landry.pdf","rel":"webarchive"},
        {"url":"https://web.archive.org/web/20050624182645/http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"webarchive"},
        {"url":"https://web.archive.org/web/20050601001748/http://www.gravity.uwa.edu.au:80/amaldi/papers/Landry.pdf","rel":"webarchive"}
      ],
      "state":"active"
      ...
    },
    ...
  ]
'''