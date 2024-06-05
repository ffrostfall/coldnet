local statement = ...

statement.clientWrite("u8", "reliable", "p1")
statement.serverWrite("u8", "p1")
