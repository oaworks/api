
# the typical reason to run only on one env is to avoid 
# unnecessary double loading of very large datasets
# or to run only on dev during testing, or only live when not relevant to dev any more
# or to run the same thing but on different schedules on dev and live
# see /status endpoint to see what has been added to the schedule object
# default is to run on both, so specify which one NOT to run on by setting _dev or _live to false


# running these only on dev
P.src.crossref.changes._schedule = '0 1 * * *'
P.src.crossref.changes._live = false

P.src.rs.changes._schedule = '0 1 * * *'
P.src.rs.changes._live = false

# these are disabled as openalex load / change mechanism is changed and we have not updated
#P.src.openalex.changes._schedule = '0 2 * * *'
#P.src.openalex.changes._live = false


# running these only on live
P.src.doaj.journals.load._schedule = '30 4 * * 1'
P.src.doaj.journals.load._dev = false

P.src.pubmed.changes._schedule = '55 5 * * *'
P.src.pubmed.changes._dev = false

P.permissions.journals._schedule = '0 5 * * *'
P.permissions.journals._dev = false
P.permissions.publishers._schedule = '10 5 * * *'
P.permissions.publishers._dev = false
P.permissions.affiliations._schedule = '15 5 * * *'
P.permissions.affiliations._dev = false

P.report.works.queries._schedule = '0 21 * * *'
P.report.works.queries._dev = false


# running these on dev and live
P.report._doqueue._schedule = 'loop'
P.report._doreversequeue._schedule = 'loop'

P.report.orgs.supplements.load._schedule = '0 */6 * * *'

P.report.suggestify._schedule = '0 18 * * 6'



