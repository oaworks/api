
P.metadata = (doi) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'
P.metadata._log = false

P.find = (options, metadata={}, content) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'

P.citation = (citation) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'
