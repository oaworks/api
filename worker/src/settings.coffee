S.mail ?= {}
S.mail.from ?= "alert@cottagelabs.com"
S.mail.to ?= "mark@cottagelabs.com"

S.src.google ?= {}
try S.src.google.secrets = JSON.parse SECRETS_GOOGLE
