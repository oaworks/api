
import puppeteer from 'puppeteer'

# puppeteer default meteor npm install should install chromium for itself to use, but it fails to find it
# wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add - 
# sudo sh -c 'echo "deb https://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'
# sudo apt-get update
# sudo apt-get install google-chrome-stable
# and check "which google-chrome" does give the path used below
P.puppet = (url, proxy, headers, idle=false) ->
  try url ?= @params.url
  return '' if not url? or typeof url isnt 'string'
  if url.indexOf('.pdf') isnt -1 or url.indexOf('/pdf') isnt -1 or url.indexOf('.doc') isnt -1
    try
      return await @fetch url # what about timeout, encoding, and getting the content?
    catch
      return ''

  try
    pid = false
    bopts = ignoreHTTPSErrors:true, dumpio:false, timeout:12000 #, headless: true # see https://github.com/puppeteer/puppeteer/issues/665
    # uncomment the following 2 options if found not to be cause of unexplained timeouts, as they seemed like good options to use
    bopts.args = ['--no-sandbox', '--disable-setuid-sandbox'] #, '--single-process', '--no-zygote']
    bopts.args.push('--proxy-server='+proxy) if proxy
    try
      browser = await puppeteer.launch bopts
    catch
      bopts.executablePath = '/usr/bin/google-chrome'
      browser = await puppeteer.launch bopts
    try pid = browser.process().pid

    try
      page = await browser.newPage()
      if typeof headers isnt 'string'
        try
          headers = JSON.parse headers
        catch
          headers = {}
      page.setExtraHTTPHeaders(headers) if typeof headers is 'object' and JSON.stringify(headers) isnt '{}'
      popts = {timeout:30000} # default is 30s anyway, but just in case want to adjust later
      # may be worth always waiting for idle, and having the idle option default to true and only override with false when necessary
      popts.waitUntil = if typeof idle is 'string' then idle else if idle then ['load','domcontentloaded','networkidle0','networkidle2'] else 'domcontentloaded'
      opened = await page.goto url, popts
      try
        content = await page.evaluate(() => new XMLSerializer().serializeToString(document.doctype) + '\n' + document.documentElement.outerHTML)
      catch
        content = await page.evaluate(() => document.querySelector('*').outerHTML)
      await page.close()
    catch err
      console.log err
    finally
      await browser.close()
    try process.kill(pid) if pid
    return content
  catch
    return ''

P.puppet._auth = 'system'
P.puppet._hide = true

# TODO check if puppet still manages to leave chrome zombies everywhere despite all the above
# (many things have been tried, on different settings etc, eventually some always seem to leak through)
# if so run a daily? cleanup to kill any chrome processes more than a day? old