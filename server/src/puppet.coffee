
import puppeteer from 'puppeteer'

# puppeteer default meteor npm install should install chromium for itself to use, but it fails to find it
# so try adding chrome to the machine directly (which will have to be done for any cluster machines)
# wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
# sudo sh -c 'echo "deb https://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
# sudo apt-get update
# sudo apt-get install google-chrome-stable
# and check that which google-chrome does give the path used below (could add a check of this, and output something if not found
# or even do the install? Could make this the necessary way to go for other things that include machine installations too
# they could have an install function which must run if the which command cannot find the expected executable
# then once the which command can find one, just use that
# TODO use some checks to see where the installed chrome/chromium is, if it is there
# if not, try to get it using browserFetcher https://github.com/GoogleChrome/puppeteer/blob/master/docs/api.md#class-browserfetcher
# tracking and re-using open chrome browsers appears to leave more hanging and use more memory than just opening and closing one every time
# tried with counters and also with counting the pages the browser thinks are open - not reliable enough, so go back to opening then closing every time
#_puppetEndpoint = false
#_puppetPages = 0
P.puppet = (url) ->
  try url ?= @params.url
  return '' if not url? or typeof url isnt 'string'
  if url.indexOf('.pdf') isnt -1 or url.indexOf('/pdf') isnt -1 or url.indexOf('.doc') isnt -1
    try
      return await @fetch url # what about timeout, encoding, and getting the content?
    catch
      return ''

  try
    args = ['--no-sandbox', '--disable-setuid-sandbox']
    args.push('--proxy-server='+proxy) if proxy
    pid = false
    try
      if typeof headers isnt 'string'
        try
          headers = JSON.parse headers
        catch
          headers = {}
      browser = await puppeteer.launch({args:args, ignoreHTTPSErrors:true, dumpio:false, timeout:12000 }) #, executablePath: '/usr/bin/google-chrome'})
      try pid = browser.process().pid
      page = await browser.newPage()
      page.setExtraHTTPHeaders(headers) if typeof headers is 'object' and JSON.stringify(headers) isnt '{}'
      popts = {timeout:30000} # default is 30s anyway, but just in case want to adjust later
      # may be worth always waiting for idle, and having the idle option default to true and only override with false when necessary
      popts.waitUntil = if typeof idle is 'string' then idle else if idle then ['load','domcontentloaded','networkidle0','networkidle2'] else 'domcontentloaded'
      opened = await page.goto url, popts
      content = await page.evaluate(() => new XMLSerializer().serializeToString(document.doctype) + '\n' + document.documentElement.outerHTML)
      # NOTE may want to change the above if trying to use puppeteer to access XML or other such things
      #content = await page.evaluate(() => document.querySelector('*').outerHTML)
      await page.close()
      await browser.close()
      return content
    catch err
      process.kill(pid) if pid
      return ''
    finally
      return ''
  catch
    return ''
