Database  country  country.txt __SQLDSN__
#ifdef SQLUSER
Database  country  USER         __SQLUSER__
#endif
#ifdef SQLPASS
Database  country  PASS         __SQLPASS__
#endif
Database  country  COLUMN_DEF   "code=CHAR(3) NOT NULL PRIMARY KEY"
Database  country  COLUMN_DEF   "selector=CHAR(3) NOT NULL"
Database  country  COLUMN_DEF   "shipmodes=CHAR(64)"
Database  country  COLUMN_DEF   "name=CHAR(32) NOT NULL"
Database  country  ChopBlanks   1
