#include "SimpleRoutingTree.h"

//#include "printf.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC;

#if defined(DELUGE)
	components DelugeC;
#endif

#ifdef PRINTFDBG_MODE
		components PrintfC;
#endif
    components MainC,ActiveMessageC;
    components new TimerMilliC() as RoutingMsgTimerC;
    components new TimerMilliC() as LostTaskTimerC;
    components new TimerMilliC() as MsgTimerC;
    components new TimerMilliC() as ReadingTimerC;
    components new TimerMilliC() as AdTimerC;
    components new TimerMilliC() as AdResponseTimerC;

    //Active Messages
    components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
    components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
    components new AMSenderC(AM_QUERYMSG) as QuerySenderC;
    components new AMReceiverC(AM_QUERYMSG) as QueryReceiverC;
    components new AMSenderC(AM_ADMSG) as AdSenderC;
    components new AMReceiverC(AM_ADMSG) as AdReceiverC;
    components new AMSenderC(AD_RESPONSE_MSG) as AdResponseSenderC;
    components new AMReceiverC(AD_RESPONSE_MSG) as AdResponseReceiverC;

    //Packet Queues
    components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
    components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
    components new PacketQueueC(SENDER_QUEUE_SIZE) as MsgSendQueueC;
    components new PacketQueueC(RECEIVER_QUEUE_SIZE) as MsgReceiveQueueC;
    components new PacketQueueC(SENDER_QUEUE_SIZE) as AdSendQueueC;
    components new PacketQueueC(RECEIVER_QUEUE_SIZE) as AdReceiveQueueC;
    components new PacketQueueC(SENDER_QUEUE_SIZE) as AdResponseSendQueueC;
    components new PacketQueueC(RECEIVER_QUEUE_SIZE) as AdResponseReceiveQueueC;

    SRTreeC.Boot->MainC.Boot;

    SRTreeC.RadioControl -> ActiveMessageC;
    SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
    SRTreeC.LostTaskTimer-> LostTaskTimerC;
    SRTreeC.MsgTimer-> MsgTimerC;
    SRTreeC.ReadingTimer-> ReadingTimerC;
    SRTreeC.AdTimer-> AdTimerC;
    SRTreeC.AdResponseTimer-> AdResponseTimerC;

    //Routing
    SRTreeC.RoutingPacket->RoutingSenderC.Packet;
    SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;
    SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
    SRTreeC.RoutingReceive->RoutingReceiverC.Receive;

    //TAG-Query
    SRTreeC.QueryPacket -> QuerySenderC.Packet;
    SRTreeC.QueryAMPacket -> QuerySenderC.AMPacket;
    SRTreeC.QueryAMSend -> QuerySenderC.AMSend;
    SRTreeC.QueryReceive -> QueryReceiverC.Receive;

    //Leach-Ad
    SRTreeC.AdPacket -> AdSenderC.Packet;
    SRTreeC.AdAMPacket -> AdSenderC.AMPacket;
    SRTreeC.AdAMSend -> AdSenderC.AMSend;
    SRTreeC.AdReceive -> AdReceiverC.Receive;

    //Leach-AdResponse
    SRTreeC.AdResponsePacket -> AdResponseSenderC.Packet;
    SRTreeC.AdResponseAMPacket -> AdResponseSenderC.AMPacket;
    SRTreeC.AdResponseAMSend -> AdResponseSenderC.AMSend;
    SRTreeC.AdResponseReceive -> AdResponseReceiverC.Receive;

    //Queues
    SRTreeC.RoutingSendQueue->RoutingSendQueueC;
    SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
    SRTreeC.MsgSendQueue->MsgSendQueueC;
    SRTreeC.MsgReceiveQueue->MsgReceiveQueueC;
    SRTreeC.AdSendQueue->AdSendQueueC;
    SRTreeC.AdReceiveQueue->AdReceiveQueueC;
    SRTreeC.AdResponseSendQueue->AdResponseSendQueueC;
    SRTreeC.AdResponseReceiveQueue->AdResponseReceiveQueueC;

}
