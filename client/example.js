
// REPORT TEMPLATE PAGE (currently bmgf.njs)

base = 'https://bg.beta.oa.works/report/'

let org = ''

oareport = function(ROR) {
  org = axios.get(base + /orgs/ + ROR)
  logo = org.logo
  document.querySelector('#logo').innerHTML(logo)

	qry = org.query.articles
	articles = axios.get(base + '/count...' + qry)
	oaArticles = '...'
	axios.all(...).then(
		axios.spread(...responses) => {
       const articles = responses[0].data, ...
       articlesContents.innerHTML = articles;
     })).catch(error => console.error(error));

}

oareport(window.location.pathname) // Bill & Melinda Gates Foundation rorABC123
oareport('Bill & Melinda Gates Foudnation') // figure out to get this from window.lcoation once we know how netlify will handle URL routing

articles = function() {
  axios.get(base + 'articles' + org.qyuery.articles)
  for (article in responses) {
    #articleTable.append('<tr>.... <a class="emailtempalte" href="' + article.DOI + '">EMail template</a></tr>')
  }
}

emailTemplate = function(e) {
  doi = e.target.attr('href')
  email = axios.get(base + '/emails/' + doi)
  template = org.template
  template = template.replace('XXEMAILXX', email) {{DOI}}
  nj.insert(email, email)
  document.querySelector('#templateEMailBox').innerHTML(template).show()
}

document.on('click', '.emailtemplate', emailTemplate)


// FRONT PAGE
autocomplete = function() {
  // debounce 300ms
  typed = #searchbox.value
  suggestions = axios.get(base + 'suggest/' + typed)
  for (res in responses.hits.hits) {
    document.querySelector('#suggestions').innerHTML(res.name)
  }
}

document.on('keyUp', '#searchbox', autocomplete)


goto = function() {
  where = #searchbox.value
  window.location = '/' + where.ROR
}
document.on('enter', '#searchbox', goto)