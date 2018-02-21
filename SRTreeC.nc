#include <stdint.h>
#include "SimpleRoutingTree.h"
#include <time.h>
#include <stdlib.h>
#include <math.h>


#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif

module SRTreeC{
	uses interface Boot;
	uses interface SplitControl as RadioControl;

	//Active Messages
	uses interface AMSend as RoutingAMSend; //Routing
	uses interface AMPacket as RoutingAMPacket;
	uses interface Packet as RoutingPacket;
	uses interface Receive as RoutingReceive;

	uses interface AMSend as QueryAMSend;	//TAG-Query
	uses interface AMPacket as QueryAMPacket;
	uses interface Packet as QueryPacket;
	uses interface Receive as QueryReceive;

    uses interface AMSend as AdAMSend;	//Leach-Ad
    uses interface AMPacket as AdAMPacket;
    uses interface Packet as AdPacket;
	uses interface Receive as AdReceive;

    uses interface AMSend as AdResponseAMSend;	//Leach-AdResponse
    uses interface AMPacket as AdResponseAMPacket;
    uses interface Packet as AdResponsePacket;
	uses interface Receive as AdResponseReceive;

	//Timers
	uses interface Timer<TMilli> as RoutingMsgTimer;
	uses interface Timer<TMilli> as LostTaskTimer;
	uses interface Timer<TMilli> as MsgTimer;
	uses interface Timer<TMilli> as ReadingTimer;
	uses interface Timer<TMilli> as AdTimer;
	uses interface Timer<TMilli> as AdResponseTimer;

	//Queues
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	uses interface PacketQueue as MsgSendQueue;
	uses interface PacketQueue as MsgReceiveQueue;
	uses interface PacketQueue as AdSendQueue;
	uses interface PacketQueue as AdReceiveQueue;
	uses interface PacketQueue as AdResponseSendQueue;
	uses interface PacketQueue as AdResponseReceiveQueue;
}
implementation
{
    //Current Epoch
	uint16_t  roundCounter;

    //Messages
    message_t radioRoutingSendPkt;
	message_t radioQuerySendPkt;
    message_t radioAdPkt;
    message_t radioAdResponsePkt;

    //Bool flags
	bool RoutingSendBusy=FALSE;
	bool lostRoutingSendTask=FALSE;
	bool lostRoutingRecTask=FALSE;

    //Local vars (Maybe change the uint bits?)
	uint8_t curdepth;
	uint16_t parentID;
    uint16_t reading;
    ChildVal myChildren[MAX_CHILDREN];  //Cache

    //Tasks
	task void sendRoutingTask();
	task void receiveRoutingTask();
    task void sendQueryTask();
    task void receiveQueryTask();
    task void sendAdTask();
    task void receiveAdTask();
    task void sendAdResponseTask();
    task void receiveAdResponseTask();

    //Funcs
    bool IamClusterhead();

    //LEACH vars
    float P = 0.25;
    uint16_t LeachRound;        //Current Leach round
    uint16_t lastRoundIwasCH;   //The last round this node was a CH.
    uint16_t curCH;             //Current CH
    uint8_t gotThisCHatRound;        //Number of rounds we have the same CH. If it exceeds 5 we just missed a new ad.

    bool wasCHatRoundZero=FALSE;      //True if this node was CH at the begining.Cant be ellected again for a few rounds.
    bool I_AM_CH=FALSE;
    bool sentToCH = FALSE;            //Successfully sent msg to CH.

    void setLostRoutingSendTask(bool state){
		atomic{
			lostRoutingSendTask=state;
		}
	}

	void setLostRoutingRecTask(bool state){
		atomic{
		    lostRoutingRecTask=state;
		}
	}

	void setRoutingSendBusy(bool state){
		atomic{
		    RoutingSendBusy=state;
		}
	}

	event void Boot.booted(){
        srand(time(NULL));   // should only be called once

		call RadioControl.start();

		setRoutingSendBusy(FALSE);

		roundCounter = 0;
        LeachRound = 0;
        gotThisCHatRound = 0;

		if(TOS_NODE_ID==0){
			curdepth=0;
			parentID=0;
		}else{
			curdepth=-1;
			parentID=-1;
		}
        curCH = ERROR_CH;
        lastRoundIwasCH = ERROR_CH;
    }

	event void RadioControl.startDone(error_t err){
		if (err == SUCCESS){
            //Initialise the children table.
            uint8_t i;
            for (i=0;i<MAX_CHILDREN;i++){
                myChildren[i].senderID = 0;
            }

            reading = FAKE_READINGS ? 10 : rand() % 21 + TOS_NODE_ID;

            if(TOS_NODE_ID == 0){
                //For the first routing.
                call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);

                //Leach start ad
                call AdTimer.startPeriodicAt(-(LEACH_ROUND_DURATION - TIMER_FAST_PERIOD * TOS_NODE_ID), LEACH_ROUND_DURATION);

                //Leach ad response. Multiple responses per LeachRound
                call AdResponseTimer.startPeriodicAt(-((2 / 3.0) * EPOCH + TIMER_VFAST_MILI * TOS_NODE_ID), EPOCH);

                //Query submission.
                call MsgTimer.startPeriodicAt(-((1 / 3.0) * EPOCH - TIMER_VFAST_MILI * TOS_NODE_ID), EPOCH);
            }else{
                call ReadingTimer.startPeriodicAt(0, EPOCH);
            }
    	}else{
            dbg("SRTreeC","Radio initialization failed! Retrying...\n");
   			call RadioControl.start();
		}
	}

	event void RadioControl.stopDone(error_t err){
	            dbg("SRTreeC","Radio stopped!\n");
	}

    /**
     * Leach Phase 3
     */
    event void MsgTimer.fired(){
        message_t tmp;
        QueryMsg *qpkt;
        uint8_t i;
        uint8_t count = 0;
        uint16_t sum = 0;
        uint16_t sum_squared = 0;
        float avg,var;

        dbg("SRTreeC", "MsgTimer fired!\n");
        roundCounter++;

        if (call MsgSendQueue.full()){
            dbg("SRTreeC", "MsgSendQueue full!\n");
            return;
        }

        qpkt = (QueryMsg *) (call QueryPacket.getPayload(&tmp, sizeof(QueryMsg)));
        if (qpkt == NULL) {
            dbg("SRTreeC", "qpkt == NULL!\n");
            return;
        }

        //Collect everything from cache
        for (i=0;i < MAX_CHILDREN && myChildren[i].senderID != 0;i++){
            sum = sum + myChildren[i].sum;
            sum_squared = sum_squared + myChildren[i].sum_squared;
            count = count + myChildren[i].count;
            dbg("dbg","Cache val[%d]: %u %u %u from %u\n",
                i,myChildren[i].sum, myChildren[i].sum_squared, myChildren[i].count, myChildren[i].senderID);
        };

        if(TOS_NODE_ID == 0){   //If root then just end the round and print the results.
            atomic{
                    sum = sum + reading;
                    sum_squared = sum_squared + pow(reading, 2);
                    count = count + 1;
                    dbg("dbg","ROOT readings: %u %u %u \n",sum,sum_squared,count);

                    avg = sum / (float) count;
                    var = sum_squared / (float) count - pow(avg, 2);
            };

            dbg("SRTreeC", "######## ROUND %u ######## \n\n", roundCounter);
            dbg("Readings", "LEACH ROUND:%u EPOCH:%u -> sum: %u | count: %u | sum_squared: %u | avg: %.2f | var: %.2f\n\n",
                LeachRound, roundCounter, sum, count, sum_squared, avg, var);
            dbg("OUT","%.2f %.2f\n",avg,var);

        } else if (I_AM_CH) { //CH just aggregates only his readings and AdResponses and then forwards them to its parent.
            atomic{
                    sum = sum + reading;
                    sum_squared = sum_squared + pow(reading, 2);
                    count = count + 1;
                    dbg("dbg","CH readings: %u %u %u \n",sum,sum_squared,count);

                    qpkt->sum = sum;
                    qpkt->sum_squared = sum_squared;
                    qpkt->count = count;
            };

            dbg("dbg", "CH Aggregate: ParentID:%u Epoch:%u sum:%u count:%u sum_sq:%u curdepth:%u\n",
                parentID, roundCounter, sum, count, sum_squared, curdepth);

            call QueryAMPacket.setDestination(&tmp, parentID);
            call QueryPacket.setPayloadLength(&tmp, sizeof(QueryMsg));

            if (call MsgSendQueue.enqueue(tmp) == SUCCESS) {
                if (call MsgSendQueue.size() == 1){
                    post sendQueryTask();
                    dbg("SRTreeC", "MsgTimer.fired(): Task posted.\n");
                }
            } else {
                dbg("ERROR", "MsgTimer.fired(): Failed to enqueue QueryMsg.\n");
            }
        } else { //Just a standard node
            atomic{
                    if (sum == 0){
                        return;
                    }

                    qpkt->sum = sum;
                    qpkt->sum_squared = sum_squared;
                    qpkt->count = count;
            };

            dbg("dbg", "STANDARD_NODE: ParentID:%u Epoch:%u sum:%u count:%u sum_sq:%u curdepth:%u\n",
                parentID, roundCounter, sum, count, sum_squared, curdepth);

            call QueryAMPacket.setDestination(&tmp, parentID);
            call QueryPacket.setPayloadLength(&tmp, sizeof(QueryMsg));

            if (call MsgSendQueue.enqueue(tmp) == SUCCESS) {
                if (call MsgSendQueue.size() == 1){
                    post sendQueryTask();
                    dbg("SRTreeC", "MsgTimer.fired(): Task posted.\n");
                }
            } else {
                dbg("ERROR", "MsgTimer.fired(): Failed to enqueue QueryMsg.\n");
            }
        }
    }

    event void QueryAMSend.sendDone(message_t * msg , error_t err){
        dbg("SRTreeC","QueryAMSend.sendDone: %s\n",(err == SUCCESS)?"True":"False");
        if(!(call MsgSendQueue.empty())){
            post sendQueryTask();
        }
    }


    event void AdAMSend.sendDone (message_t * msg , error_t err){
        dbg("SRTreeC","AdAMSend.sendDone: %s\n",(err == SUCCESS)?"True":"False");
        if(!(call AdSendQueue.empty())){
            post sendAdTask();
        }
    }

    /**
     * Receive an ad from a current CH.
     */
    event message_t* AdReceive.receive ( message_t * msg , void * payload, uint8_t len){
        message_t tmp;
        uint16_t msource;

        msource = call AdAMPacket.source(msg);
        dbg("SRTreeC", "AdReceive.receive from %u\n",  msource);

        atomic{
            memcpy(&tmp,msg,sizeof(message_t));
        }

        if(call AdAMPacket.isForMe(&tmp)){
            if (call AdReceiveQueue.enqueue(tmp) != SUCCESS){
                dbg("SRTreeC","AdMsg enqueue failed! \n");
            } else {
                post receiveAdTask();
            }
        }

        return msg;
    }

    event void AdResponseAMSend.sendDone (message_t * msg , error_t err){
        dbg("SRTreeC","AdResponseAMSend.sendDone: %s\n",(err == SUCCESS)?"True":"False");
        sentToCH = TRUE;
        if(!(call AdResponseSendQueue.empty())){
            post sendAdResponseTask();
        }
    }

    /**
     * Someone responed to my ads as CH.
     */
    event message_t* AdResponseReceive.receive ( message_t * msg , void * payload, uint8_t len){
        message_t tmp;
        uint16_t msource;

        msource = call AdResponseAMPacket.source(msg);
        atomic{
            memcpy(&tmp,msg,sizeof(message_t));
        }

        msource = call AdAMPacket.source(msg);
        if(call AdResponseAMPacket.isForMe(&tmp)){
            if (call AdResponseReceiveQueue.enqueue(tmp) != SUCCESS){
                dbg("SRTreeC","AdResponseMsg enqueue failed! \n");
            } else {
                post receiveAdResponseTask();
            }
        }

        dbg("SRTreeC", "AdResponseReceive.receive from %u\n",  msource);
        return msg;
    }

    event message_t* QueryReceive.receive( message_t * msg , void * payload, uint8_t len){
        message_t tmp;
        uint16_t msource;

        msource = call QueryAMPacket.source(msg);

        dbg("SRTreeC", "QueryReceive.receive from %u\n",  msource);

        atomic{
            memcpy(&tmp,msg,sizeof(message_t));
        }

        if(call QueryAMPacket.isForMe(&tmp)){
            if (call MsgReceiveQueue.enqueue(tmp) != SUCCESS){
                dbg("SRTreeC","QueryMsg enqueue failed! \n");
            } else {
                post receiveQueryTask();
            }
        }
        return msg;
    }

    /**
     * Produces random or fake readings.
     */
    event void ReadingTimer.fired(){
        reading = FAKE_READINGS ? 10 : rand() % 21 + TOS_NODE_ID;
        dbg("Values", "\nreading: %u", reading);
    }

    /**
     * Fired when a task needs to be resubmited.
     */
	event void LostTaskTimer.fired(){
		if (lostRoutingSendTask){
			post sendRoutingTask();
			setLostRoutingSendTask(FALSE);
		}

		if (lostRoutingRecTask){
			post receiveRoutingTask();
			setLostRoutingRecTask(FALSE);
		}
	}

    /**
     * 1st phase of the epoch.
     * Decide if this node is a CH.
     * If so BROADCAST!
     */
    event void AdTimer.fired(){
        message_t tmp;
        AdMsg* mrpkt;
        uint8_t i;

        dbg("dbg", "AdTimer.fired() \n");

        for (i=0;i<MAX_CHILDREN;i++){   //Flush the cache as new CHs = completely different readings.
            myChildren[i].senderID = 0;
        }

        atomic{
                I_AM_CH = IamClusterhead();
                LeachRound++;
        };

        if (I_AM_CH) {
            dbg("SRTreeC", "I am a CH!\n");
        } else {
            dbg("SRTreeC", "I am NOT a CH!\n");
            return;
        }

        if (call AdSendQueue.full()){
            dbg("SRTreeC","AdSendQueue is FULL!!! \n");
            return;
        }

        mrpkt = (AdMsg*) (call AdPacket.getPayload(&tmp, sizeof(AdMsg)));

        if(mrpkt==NULL){
            dbg("SRTreeC","AdTimer.fired(): No valid payload... \n");
            return;
        }

        atomic{
                mrpkt->senderID=TOS_NODE_ID;
        }

        dbg("SRTreeC","AdMsg sending...!!!! \n", TOS_NODE_ID);

        call AdAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
        call AdPacket.setPayloadLength(&tmp, sizeof(AdMsg));

        if( call AdSendQueue.enqueue(tmp) == SUCCESS){
            if (call AdSendQueue.size()==1){
                dbg("SRTreeC","sendAdTask() posted!!\n");
                post sendAdTask();
            }
            dbg("SRTreeC","AdMsg enqueued successfully in AdSendQueue!!!\n");
        }else{
            dbg("SRTreeC","AdMsg failed to be enqueued in AdSendQueue!!!\n");
        }
    }

    /**
     * 2nd phase of the Epoch.
     * Select your CH and send him your readings.
     */
    event void AdResponseTimer.fired(){
        message_t tmp;
        AdResponseMsg* msg;

        dbg("SRTreeC", "AdResponseTimer fired!\n");
        sentToCH = FALSE;

        if (call AdResponseSendQueue.full()){
            dbg("SRTreeC", "AdResponseSendQueue full!\n");
            return;
        }

        if(I_AM_CH){
            dbg("dbg","CHs dont send AdResponses!\n");
            return;
        }

        if(curCH == ERROR_CH){
            //Become a CH if you couldnt find someone.
            I_AM_CH = TRUE;
            dbg("dbg","Upgraded to CH!!\n");
            return;
        }


        if(abs(gotThisCHatRound - LeachRound)>1){ //Become a CH if you havent heard from a CH for
            I_AM_CH = TRUE;
            dbg("dbg","Upgraded to CH because of gotThisCHatRound-LeachRound (%u-%u) !!\n",gotThisCHatRound,LeachRound);
            return;
        }

        msg = (AdResponseMsg *) (call AdResponsePacket.getPayload(&tmp, sizeof(AdResponseMsg)));

        if (msg == NULL) {
            dbg("SRTreeC", "msg == NULL!\n");
            return;
        }

        //Load the values and send it to your father.
        atomic{
                msg->sum = reading;
                msg->sum_squared = pow(reading, 2);
                msg->count = 1;
        };

        dbg("dbg", "Responding to CH %u: LeachRound: %u Epoch:%u sum:%u sum_squared:%u curdepth:%u\n",
            curCH, LeachRound, roundCounter, msg->sum, msg->sum_squared, curdepth);

        call AdResponseAMPacket.setDestination(&tmp, curCH);
        call AdResponsePacket.setPayloadLength(&tmp, sizeof(AdResponseMsg));

        if (call AdResponseSendQueue.enqueue(tmp) == SUCCESS) {
            if (call AdResponseSendQueue.size() == 1){
                post sendAdResponseTask();
                dbg("SRTreeC", "AdResponseTimer.fired(): Task posted.\n");
            }
        } else {
            dbg("ERROR", "AdResponseTimer.fired(): Failed to enqueue AdResponseMsg.\n");
        }
    }

	event void RoutingMsgTimer.fired(){
		message_t tmp;

		RoutingMsg* mrpkt;
	    dbg("RoutingMsg","RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");

		if (TOS_NODE_ID == 0){
            call MsgTimer.startPeriodicAt(0, EPOCH); // Cancel previous submission and query periodically
		}

		if(call RoutingSendQueue.full()){
	        dbg("RoutingMsg","RoutingSendQueue is FULL!!! \n");
			return;
		}

		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));

		if(mrpkt==NULL){
	        dbg("RoutingMsg","RoutingMsgTimer.fired(): No valid payload... \n");
			return;
		}

		atomic{
            mrpkt->senderID=TOS_NODE_ID;
            mrpkt->depth = curdepth;
		}

	    dbg("RoutingMsg","RoutingMsg sending...!!!! \n");

		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));


		if( call RoutingSendQueue.enqueue(tmp) == SUCCESS){
			if (call RoutingSendQueue.size()==1){
	            dbg("RoutingMsg","SendTask() posted!!\n");
				post sendRoutingTask();
			}
		    dbg("RoutingMsg","RoutingMsg enqueued successfully in SendingQueue!!!\n");
		}else{
		    dbg("RoutingMsg","RoutingMsg failed to be enqueued in SendingQueue!!!\n");
		}
	}

	event void RoutingAMSend.sendDone(message_t * msg , error_t err){
		dbg("RoutingMsg","A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		setRoutingSendBusy(FALSE);
		if(!(call RoutingSendQueue.empty())){
			post sendRoutingTask();
		}
	}

	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len){
		message_t tmp;
		uint16_t msource;

		msource = call RoutingAMPacket.source(msg);
        dbg("RoutingMsg","Something Received!!!, len = %u , rm=%u\n",len, sizeof(RoutingMsg));

		atomic{
		    memcpy(&tmp,msg,sizeof(message_t));
		}

		if(call RoutingReceiveQueue.enqueue(tmp) == SUCCESS){
            dbg("RoutingMsg","posting receiveRoutingTask()!!!! \n");
			post receiveRoutingTask();
		}else{
            dbg("RoutingMsg","RoutingMsg enqueue failed!!! \n");
		}
	    dbg("RoutingMsg", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}

	////////////// Tasks implementations //////////////////////////////
    task void sendAdResponseTask(){
        uint8_t mlen;
        uint16_t mdest;

        if (call AdResponseSendQueue.empty()){
            dbg("SRTreeC", "sendAdResponse(): AdResponseSendQueue.empty()!\n");
            return;
        }

        radioAdResponsePkt = call AdResponseSendQueue.dequeue();

        mlen = call AdResponsePacket.payloadLength(&radioAdResponsePkt);
        mdest = call AdResponseAMPacket.destination(&radioAdResponsePkt);

        if (mlen != sizeof(QueryMsg)) {
            dbg("SRTreeC", "sendAdResponse(): mlen!=sizeof(QueryMsg)!\n");
            return;
        }

        if (call AdResponseAMSend.send(mdest, &radioAdResponsePkt, mlen) == SUCCESS) {
            dbg("SRTreeC", "sendAdResponse(): AdResponseAMSend.send success!\n");
        }else {
            dbg("SRTreeC", "AdResponseAMSend.send FAILED!\n");
        }
    }

    task void sendAdTask(){
        uint8_t mlen;
        uint16_t mdest;

        if (call AdSendQueue.empty()){
            dbg("SRTreeC", "sendAdTask(): AdSendQueue.empty()!\n");
            return;
        }

        radioAdPkt = call AdSendQueue.dequeue();

        mlen = call AdPacket.payloadLength(&radioAdPkt);
        mdest = call AdAMPacket.destination(&radioAdPkt);

        if (mlen != sizeof(AdMsg)) {
            dbg("SRTreeC", "sendAdTask(): mlen!=sizeof(AdMsg)!\n");
            return;
        }

        if (call AdAMSend.send(mdest, &radioAdPkt, mlen) == SUCCESS) {
            dbg("SRTreeC", "sendAdTask(): AdAMSend.send success!\n");
        }else {
            dbg("SRTreeC", "AdAMSend.send FAILED!\n");
        }
    }

    task void receiveAdTask(){
        uint8_t len;
        message_t AdRcvPkt;
        AdMsg* mpkt;

        uint16_t msg_sender;

        if (call AdReceiveQueue.empty()){
            dbg("SRTreeC", "AdReceiveQueue():AdReceiveQueue.empty()!\n");
            return;
        }

        AdRcvPkt = call AdReceiveQueue.dequeue();
        len = call AdPacket.payloadLength(&AdRcvPkt);

        if (len != sizeof(AdMsg)) {
            dbg("SRTreeC", "receiveAdTask(): len!=sizeof(AdMsg)!\n");
            return;
        }

        mpkt = (AdMsg * )(call AdPacket.getPayload(&AdRcvPkt, sizeof(AdMsg)));

        msg_sender = mpkt->senderID;

        if (I_AM_CH){
            dbg("dbg","Discarding received Ad from %u because I am a CH!\n",msg_sender);
        } else {
            atomic{
                    curCH = msg_sender;
                    gotThisCHatRound = LeachRound;
            };
            dbg("dbg","Accepted Ad from %u\n",msg_sender);
        }
    }

	task void sendQueryTask(){
        uint8_t mlen;
        uint16_t mdest;

        if (call MsgSendQueue.empty()){
            dbg("SRTreeC", "sendQueryTask(): MsgSendQueue.empty()!\n");
            return;
        }

        radioQuerySendPkt = call MsgSendQueue.dequeue();

        mlen = call QueryPacket.payloadLength(&radioQuerySendPkt);
        mdest = call QueryAMPacket.destination(&radioQuerySendPkt);

        if (mlen != sizeof(QueryMsg)) {
            dbg("SRTreeC", "sendQueryTask(): mlen!=sizeof(QueryMsg)!\n");
            return;
        }

        if (call QueryAMSend.send(mdest, &radioQuerySendPkt, mlen) == SUCCESS) {
            dbg("SRTreeC", "sendQueryTask(): QueryAMSend.send success!\n");
        }else {
            dbg("SRTreeC", "sendQueryAMSend.send FAILED!\n");
        }
    }

	task void sendRoutingTask(){
		uint8_t mlen;
		uint16_t mdest;

        dbg("RoutingMsg","SendRoutingTask(): Starting....\n");

		if (call RoutingSendQueue.empty()){
            dbg("RoutingMsg","sendRoutingTask():Q is empty!\n");
			return;
		}

		if(RoutingSendBusy) {
            dbg("RoutingMsg","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			setLostRoutingSendTask(TRUE);
			return;
		}

		radioRoutingSendPkt = call RoutingSendQueue.dequeue();

		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt);
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt);

		if(mlen!=sizeof(RoutingMsg)){
            dbg("RoutingMsg","\t\tsendRoutingTask(): Unknown message!!!!\n");
			return;
		}

        if (call RoutingAMSend.send(mdest, &radioRoutingSendPkt, mlen) == SUCCESS){
            dbg("RoutingMsg","sendRoutingTask(): Send returned success!!!\n");
			setRoutingSendBusy(TRUE);
		}else{
            dbg("RoutingMsg","SendRoutingTask(): send failed!!!\n");
			setRoutingSendBusy(FALSE);
		}
	}

	/**
	 * Dequeues a message and processes it.
	 */
	task void receiveRoutingTask() {
		uint8_t len;
		message_t radioRoutingRecPkt;

		radioRoutingRecPkt = call RoutingReceiveQueue.dequeue();
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
        dbg("RoutingMsg","ReceiveRoutingTask(): len=%u!\n",len);


		if(len == sizeof(RoutingMsg)){ // processing of radioRecPkt, pos tha xexorizo ta 2 diaforetika minimata??
            RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len));
            dbg("RoutingMsg","RoutingMsg received! \n");
            dbg("RoutingMsg","receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);

            //Does NOT have a parent. Get a new one.
			if ( parentID<0 || parentID>=65535 ){
                parentID = call RoutingAMPacket.source(&radioRoutingRecPkt);
				curdepth = mpkt->depth + 1;

                dbg("SRTreeC","curdepth= %d , parentID= %d \n", curdepth , parentID);

                /**
                 * Slice the avialable EPOCH in 3 parts.
                 * 1) CHs advertise
                 * 2) Non-CH nodes join their favorite CHs.
                 * 3) Boring aggregatation things.
                 *
                 * Periodic timers set in the past will get a bunch of events in succession,until the timer "catches up".
                 * Timers also wrap around.Mul is used to scale up/down our time slot as the EPOCH is usually TOO big
                 * and is wasted. Dont overdo it though as it drains battery. The rand() at the end is used to avoid
                 * more collisions.
                 */
                if(TOS_NODE_ID != 0){
                    //Replace the 1st arg of MsgTimer with this to revert to the original TAG-like configuration.
                    //start = -MUL * (curdepth * TIMER_FAST_PERIOD + TIMER_VFAST_MILI * TOS_NODE_ID + rand() % 10 * MUL);

                    //For the first routing.
                    call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);

                }
                //Leach start ad
                call AdTimer.startPeriodicAt(-(LEACH_ROUND_DURATION - TIMER_FAST_PERIOD * TOS_NODE_ID), LEACH_ROUND_DURATION);

                //Leach ad response. Multiple responses per LeachRound
                call AdResponseTimer.startPeriodicAt(-((2 / 3.0) * EPOCH + TIMER_VFAST_MILI * TOS_NODE_ID), EPOCH);

                //Query submission.
                call MsgTimer.startPeriodicAt(-((1 / 3.0) * EPOCH + TIMER_VFAST_MILI * TOS_NODE_ID), EPOCH);
            }
		}else{
            dbg("dbg","receiveRoutingTask():Empty message!!! \n");
		}
	}

    task void receiveQueryTask(){
        uint8_t len;
        uint16_t msource;
        message_t queryRcvPkt;
        uint8_t i;

        queryRcvPkt = call MsgReceiveQueue.dequeue();
        len = call QueryPacket.payloadLength(&queryRcvPkt);
        msource = call QueryAMPacket.source(&queryRcvPkt);  //Child that sent the message

        if(len == sizeof(QueryMsg)){
            QueryMsg *mpkts = (QueryMsg *) (call QueryPacket.getPayload(&queryRcvPkt, len));

            //Add new child to cache
            for (i = 0; i < MAX_CHILDREN; i++) {
                if (myChildren[i].senderID == 0 || myChildren[i].senderID == msource) {
                    myChildren[i].senderID = msource;
                    myChildren[i].sum = mpkts->sum;
                    myChildren[i].sum_squared = mpkts->sum_squared;
                    myChildren[i].count = mpkts->count;
                    dbg("dbg","QueryReceived from %u with values: %u %u %u\n",
                        msource, mpkts->sum, mpkts->sum_squared, mpkts->count);
                    break;
                }
            }
        } else {
            dbg("SRTreeC","receiveQueryTask():len != sizeof(QueryMsg)! \n");
        }
    }

    task void receiveAdResponseTask(){
        message_t AdResponseRcvPkt;
        uint8_t len;
        uint16_t msource;
        AdResponseMsg * mpkts;
        uint8_t i;

        dbg("SRTreeC", "receiveAdResponseTask() CH:%s\n", I_AM_CH ? "YES" : "NO");

        AdResponseRcvPkt = call AdResponseReceiveQueue.dequeue();
        len = call AdResponsePacket.payloadLength(&AdResponseRcvPkt);
        msource = call AdResponseAMPacket.source(&AdResponseRcvPkt);

        if(len == sizeof(AdResponseMsg)){
            mpkts = (AdResponseMsg *) (call AdResponsePacket.getPayload(&AdResponseRcvPkt, len));

            //Add new child to cache
            for (i = 0; i < MAX_CHILDREN; i++) {
                if (myChildren[i].senderID == 0 || myChildren[i].senderID == msource) {
                    myChildren[i].senderID = msource;
                    myChildren[i].sum = mpkts->sum;
                    myChildren[i].sum_squared = mpkts->sum_squared;
                    myChildren[i].count = mpkts->count;
                    dbg("SRTreeC","receiveAdResponseTask() Caching at %d: ID:%u SUM:%u COUNT:%u\n",i,msource,mpkts->sum,mpkts->count);
                    break;
                }
            }
        } else {
            dbg("SRTreeC","receiveAdResponseTask():len != sizeof(AdResponseMsg)! \n");
        }
    }


    /**
     * This method should be called only ONCE each round as it uses rand().
     * @return This node being a CH.
     */
    bool IamClusterhead() {
        float rand_res = rand() / (double) RAND_MAX;
        dbg("CH","CH decision with LeachRound:%u EPOCH:%u RandResult:%f\n",LeachRound,roundCounter,rand_res);

        if (TOS_NODE_ID == 0) { //Root is ALWAY CH!
            dbg("CH","CH at depth: %u at round %u | ROOT\n",curdepth,LeachRound);
            return TRUE;
        }

        if (LeachRound == 0) {               //First round.Will be executed once!
            if (rand_res < P) {
                lastRoundIwasCH = LeachRound;
                wasCHatRoundZero = TRUE;
                dbg("CH","CH at depth: %u at round %u| LeachRound == 0\n",curdepth,LeachRound);
                return TRUE;
            }else{
                return FALSE;
            }
        } else if (LeachRound < 1 / (double) P) {    //After the 1st round but before the last round of 1st ellection.Will be executed once!
            if (wasCHatRoundZero) {
                dbg("CH","NOT CH at depth: %u  at round %u | LeachRound < ((1 / P) - 1)\n",curdepth,LeachRound);
                return FALSE;
            }
        } else if (LeachRound == 1 / (double) P) {     //A round before 2nd ellection.Will be executed once!
            if (!wasCHatRoundZero){
                lastRoundIwasCH = LeachRound;
                dbg("CH","CH at depth: %u  at round %u | LeachRound == (1 / P - 1)\n",curdepth,LeachRound);
                return TRUE;
            }else{
                dbg("CH","NOT CH at depth: %u  at round %u| LeachRound == (1 / P - 1)\n",curdepth,LeachRound);
                return FALSE;
            }
        } else if (LeachRound - lastRoundIwasCH <  1 / (double) P) {  //This node has been CH in the last 1/P rounds.
            dbg("CH","NOT CH at depth: %u  at round %u | (LeachRound - lastRoundIwasCH <  1 / (double) P)\n",curdepth,LeachRound);
            return FALSE;
        }

        //Decide if this node is a CH.
        if ( rand_res < P / (1 - P * (LeachRound % ((int) (1 / (double) P))))) {
            lastRoundIwasCH = LeachRound;
            dbg("CH","CH at depth: %u  at round %u| rand() / RAND_MAX < (P / (1 - P * (LeachRound % ((int) (1 / P)))))\n",curdepth,LeachRound);
            return TRUE;
        }

        dbg("CH","NOT CH at depth: %u  at round %u | END\n",curdepth,LeachRound);
        return FALSE;
    }

}
