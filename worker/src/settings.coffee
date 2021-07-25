S.mail ?= {}
S.mail.from ?= "system@oa.works"
S.mail.to ?= "mark@oa.works"

S.src.google ?= {}
try S.src.google.secrets = JSON.parse SECRETS_GOOGLE
