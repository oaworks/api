
# for server-side cron just use node-cron, which is imported via the main server API file
# https://www.npmjs.com/package/node-cron

# any function can then be scheduled (here or in the function file, if it's a server-side function file) like so:
# cron.schedule '* * * * *', cron.example

# NOTE though that a P. function on the API is usually used once wrapped in the API call
# so those should be scheduled using the _schedule config option on their function declaration

# suitable cron values for each of the five space-separated cron locations:
# 0-59 seconds | 0-59 minutes | 0-23 hours | 1-31 monthdays | 0-7 weekdays (0 and 7 are sunday)
# multiple values can be provided for each location, separated by commas. 
# ranges can be used, such as 1-5
# or of course * wildcard can be used for any, and all * defaults to run every minute

# options can be provided as an object after the function and are 
# scheduled: true*/false
# timezone: (see https://momentjs.com/timezone/ for allowed timezone declarations)

# if a task is declared with a name e.g task = cron.schedule ...
# then .start() .stop() or .destroy() can be called on it

# Cloudflare also has a task scheduler which could be used for triggering, but that has not been done yet