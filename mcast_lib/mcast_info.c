/**
 * Copyright 2014 University Corporation for Atmospheric Research.
 * All rights reserved. See file COPYRIGHT in the top-level source-directory
 * for legal conditions.
 *
 *   @file multicast_info.c
 * @author Steven R. Emmerson
 *
 * This file defines the multicast information returned by a server.
 */

#include "config.h"

#include "inetutil.h"
#include "ldm.h"
#include "ldmprint.h"
#include "log.h"
#include "mcast_info.h"

#include <stdlib.h>
#include <string.h>
#include <xdr.h>

/*
 * IPv4 multicast address categories:
 *     224.0.0.0 - 224.0.0.255     Reserved for local purposes
 *     224.0.1.0 - 238.255.255.255 User-defined multicast addresses
 *     239.0.0.0 - 239.255.255.255 Reserved for administrative scoping
 *
 * Time-to-live of outgoing packets:
 *      0           Restricted to same host. Won't be output by any interface.
 *      1           Restricted to the same subnet. Won't be forwarded by a
 *                  router.
 *      2<=ttl<32   Restricted to the same site, organization or department.
 *     32<=ttl<64   Restricted to the same region.
 *     64<=ttl<128  Restricted to the same continent.
 *    128<=ttl<255  Unrestricted in scope. Global.
 */

/**
 * Initializes a multicast information object.
 *
 * @param[out] info       The multicast information object.
 * @param[in]  name       The name of the multicast group. The caller may free.
 * @param[in]  mcast      The Internet address of the multicast group. The
 *                        caller may free.
 * @param[in]  ucast      The Internet address of the unicast service for blocks
 *                        and files that are missed by the multicast receiver.
 *                        The caller may free.
 * @retval     true       Success. `info` is set.
 * @retval     false      Failure. \c log_add() called. The state of `info` is
 *                        indeterminate.
 */
static bool
mi_init(
    McastInfo* const restrict         info,
    const char* const restrict        name,
    const ServiceAddr* const restrict mcast,
    const ServiceAddr* const restrict ucast)
{
    ServiceAddr multi;
    ServiceAddr uni;

    if (!sa_copy(&info->group, mcast)) {
        LOG_ADD0("Couldn't copy multicast address");
        return false;
    }

    if (!sa_copy(&info->server, ucast)) {
        LOG_ADD0("Couldn't copy unicast address");
        xdr_free(xdr_ServiceAddr, (char*)&info->group);
        return false;
    }

    if ((info->mcastName = strdup(name)) == NULL) {
        LOG_SERROR0("Couldn't copy multicast group name");
        xdr_free(xdr_ServiceAddr, (char*)&info->server);
        xdr_free(xdr_ServiceAddr, (char*)&info->group);
        return false;
    }

    return true; // success
}

/******************************************************************************
 * Public API:
 ******************************************************************************/

/**
 * Returns a new multicast information object.
 *
 * @param[in] name       The name of the multicast group. The caller may free.
 * @param[in] mcast      The Internet address of the multicast group. The caller
 *                       may free.
 * @param[in] ucast      The Internet address of the unicast service for blocks
 *                       and files that are missed by the multicast receiver.
 *                       The caller may free.
 * @retval    NULL       Failure. `log_start()` called.
 * @return               The new, initialized multicast information object.
 */
McastInfo*
mi_new(
    const char* const restrict        name,
    const ServiceAddr* const restrict mcast,
    const ServiceAddr* const restrict ucast)
{
    McastInfo* const info = LOG_MALLOC(sizeof(McastInfo),
            "multicast information");

    if (mi_init(info, name, mcast, ucast))
        return info;

    free(info);

    return NULL;
}

/**
 * Frees multicast information.
 *
 * @param[in,out] mcastInfo  Pointer to multicast information to be freed or
 *                           NULL. If non-NULL, then it must have been returned
 *                           by `mi_new()`.
 */
void
mi_free(
    McastInfo* const mcastInfo)
{
    if (mcastInfo) {
        (void)xdr_free(xdr_McastInfo, (char*)mcastInfo);
        free(mcastInfo);
    }
}

/**
 * Copies multicast information. Performs a deep copy.
 *
 * @param[out] to           Destination.
 * @param[in]  from         Source. The caller may free.
 * @retval     0            Success.
 * @retval     LDM7_SYSTEM  System error. \c log_add() called.
 */
int
mi_copy(
    McastInfo* const restrict       to,
    const McastInfo* const restrict from)
{
    return mi_init(to, from->mcastName, &from->group, &from->server);
}

/**
 * Returns a formatted representation of a multicast information object that's
 * suitable as a filename.
 *
 * @param[in] info  The multicast information object.
 * @retval    NULL  Failure. `log_add()` called.
 * @return          A filename representation of `info`.
 */
const char*
mi_asFilename(
    const McastInfo* const info)
{
    return info->toString;
}