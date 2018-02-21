#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

#define MAX_CHILDREN 25

enum {
    SENDER_QUEUE_SIZE = 5,
    RECEIVER_QUEUE_SIZE = 3,
    FAKE_READINGS = 0,      //Used for debugging, turns all readings to a fixed value.
    AM_QUERYMSG = 30,       //The query msg
    AM_ADMSG = 31,          //Ad msg
    AD_RESPONSE_MSG = 32,       //AdResponse msg
    AM_ROUTINGMSG = 22,     //Routing msg
    LEACH_ROUND_DURATION = 300000,          //Leach round duration
    MUL = 1,                //Scale up/down start time
    EPOCH = 60000,
    TIMER_FAST_PERIOD = 200,
    TIMER_VFAST_MILI = EPOCH / 1000,
    ERROR_CH = 65535
};

typedef nx_struct RoutingMsg{
        nx_uint16_t senderID;   //The TOS_NODE_ID of the sender.
        nx_uint8_t depth;       //The depth of the node with TOS_NODE_ID = senderID.
}RoutingMsg;

/**
 * Query msg
 *
 * Avg = sum/count
 * Var = (sum_squares/count) - (Avg)^2
 */
typedef nx_struct QueryMsg{
        nx_uint16_t sum;
        nx_uint8_t count;
        nx_uint16_t sum_squared;
}QueryMsg;

/**
 * Leach Ad message
 */
typedef nx_struct LeachAdMsg{
        nx_uint16_t senderID;   //The TOS_NODE_ID of the CH.
}AdMsg;

/**
 * Leach Ad Response message
 */
typedef nx_struct LeachAdResponseMsg{
        nx_uint16_t sum;
        nx_uint8_t count;
        nx_uint16_t sum_squared;
}AdResponseMsg;


typedef struct ChildValue {
    uint16_t senderID;
    uint16_t sum;
    uint16_t sum_squared;
    uint8_t count;
} ChildVal;

#endif
