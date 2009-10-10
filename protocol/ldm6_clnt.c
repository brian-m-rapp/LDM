#include "ldmconfig.h"
/*
 * Please do not edit this file.
 * It was generated using rpcgen.
 */

#include <memory.h> /* for memset */
#include "ldm.h"
#include <string.h>

/* Default timeout can be changed using clnt_control() */
static struct timeval TIMEOUT = { 60, 0 };
static struct timeval ZERO_TIMEOUT = { 0, 0 };

fornme_reply_t *
feedme_6(feedpar_t *argp, CLIENT *clnt)
{
	static fornme_reply_t clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, FEEDME,
		(xdrproc_t) xdr_feedpar_t, (caddr_t) argp,
		(xdrproc_t) xdr_fornme_reply_t, (caddr_t) &clnt_res,
		TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return (&clnt_res);
}

fornme_reply_t *
notifyme_6(prod_class_t *argp, CLIENT *clnt)
{
	static fornme_reply_t clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, NOTIFYME,
		(xdrproc_t) xdr_prod_class_t, (caddr_t) argp,
		(xdrproc_t) xdr_fornme_reply_t, (caddr_t) &clnt_res,
		TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return (&clnt_res);
}

bool_t *
is_alive_6(u_int *argp, CLIENT *clnt)
{
	static bool_t clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, IS_ALIVE,
		(xdrproc_t) xdr_u_int, (caddr_t) argp,
		(xdrproc_t) xdr_bool, (caddr_t) &clnt_res,
		TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return (&clnt_res);
}

hiya_reply_t *
hiya_6(prod_class_t *argp, CLIENT *clnt)
{
	static hiya_reply_t clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, HIYA,
		(xdrproc_t) xdr_prod_class_t, (caddr_t) argp,
		(xdrproc_t) xdr_hiya_reply_t, (caddr_t) &clnt_res,
		TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return (&clnt_res);
}

void *
notification_6(prod_info *argp, CLIENT *clnt)
{
	static char clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, NOTIFICATION,
		(xdrproc_t) xdr_prod_info, (caddr_t) argp,
		(xdrproc_t) NULL, (caddr_t) &clnt_res,
		ZERO_TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return ((void *)&clnt_res);
}

void *
hereis_6(product *argp, CLIENT *clnt)
{
	static char clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, HEREIS,
		(xdrproc_t) xdr_product, (caddr_t) argp,
		(xdrproc_t) NULL, (caddr_t) &clnt_res,
		ZERO_TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return ((void *)&clnt_res);
}

comingsoon_reply_t *
comingsoon_6(comingsoon_args *argp, CLIENT *clnt)
{
	static comingsoon_reply_t clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, COMINGSOON,
		(xdrproc_t) xdr_comingsoon_args, (caddr_t) argp,
		(xdrproc_t) xdr_comingsoon_reply_t, (caddr_t) &clnt_res,
		TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return (&clnt_res);
}

void *
blkdata_6(datapkt *argp, CLIENT *clnt)
{
	static char clnt_res;

	memset((char *)&clnt_res, 0, sizeof(clnt_res));
	if (clnt_call (clnt, BLKDATA,
		(xdrproc_t) xdr_datapkt, (caddr_t) argp,
		(xdrproc_t) NULL, (caddr_t) &clnt_res,
		ZERO_TIMEOUT) != RPC_SUCCESS) {
		return (NULL);
	}
	return ((void *)&clnt_res);
}

void*
nullproc_6(void *argp, CLIENT *clnt)
{
        static char clnt_res;
        if (clnt_call(clnt, NULLPROC,
                (xdrproc_t) xdr_void, (void*) argp,
                (xdrproc_t) xdr_void, (void*) &clnt_res,
                TIMEOUT) != RPC_SUCCESS) {
            return NULL;
        }
        return ((void *)&clnt_res);
}


enum clnt_stat clnt_stat(CLIENT *clnt)
{
    struct rpc_err rpcErr;

    clnt_geterr(clnt, &rpcErr);

    return rpcErr.re_status;
}
