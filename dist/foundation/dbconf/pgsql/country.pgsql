Database  country  country.txt  __SQLDSN__
ifdef SQLUSER
Database  country  USER         __SQLUSER__
endif
ifdef SQLPASS
Database  country  PASS         __SQLPASS__
endif
Database  country  DEFAULT_TYPE VARCHAR(255)
Database  country  COLUMN_DEF   "code=VARCHAR(3) NOT NULL PRIMARY KEY"
Database  country  COLUMN_DEF   "selector=VARCHAR(3) NOT NULL"
Database  country  COLUMN_DEF   "shipmodes=VARCHAR(64)"
Database  country  COLUMN_DEF   "name=VARCHAR(64) NOT NULL"
Database  country  COLUMN_DEF   "iso=VARCHAR(3) DEFAULT '' NOT NULL"
Database  country  COLUMN_DEF   "isonum=VARCHAR(3) DEFAULT '' NOT NULL"
Database  country  INDEX        name
