package services

Replication_Transport_Event_Type :: enum {
    NONE,
    CONNECT,
    DISCONNECT,
    RECEIVE,
}

Replication_Transport_Channel_Reliable: u8 = 0
Replication_Transport_Channel_Unreliable: u8 = 1
