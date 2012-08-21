/**
 * Copyright 20012 University Corporation for Atmospheric Research.
 * See file ../COPYRIGHT for copying and redistribution conditions.
 *
 * This file contains the uldbutil(1) utility for accessing the upstream LDM
 * database.
 *
 * Created on: Aug 20, 2012
 * Author: Steven R. Emmerson
 */

#include <config.h>

#include <libgen.h>
#include <netinet/in.h>
#include <stdio.h>

#include "ldm.h"
#include "log.h"
#include "uldb.h"
#include "inetutil.h"
#include "ldmprint.h"
#include "prod_class.h"

/**
 * @retval 0    Success
 * @retval 1    Invocation error
 * @retval 2    The upstream LDM database doesn't exist
 * @retval 3    The upstream LDM database exists but couldn't be accessed
 */
int main(
        int argc,
        char* argv[])
{
    const char* const progname = basename(argv[0]);
    int status;

    (void) openulog(progname, LOG_NOTIME | LOG_IDENT, LOG_LDM, "-");
    (void) setulogmask(LOG_UPTO(LOG_NOTICE));

    if (1 < argc) {
        LOG_START0("Too many arguments");
        LOG_ADD1("Usage: %s", progname);
        log_log(LOG_ERR);
        status = 1;
    }
    else {
        if (status = uldb_open()) {
            if (ULDB_EXIST == status) {
                LOG_ADD0("The upstream LDM database doesn't exist");
                LOG_ADD0("Is the LDM running?");
                log_log(LOG_NOTICE);
                status = 2;
            }
            else {
                LOG_ADD0("Couldn't open the upstream LDM database");
                log_log(LOG_ERR);
                status = 3;
            }
        }
        else {
            uldb_Iter* iter;

            if (status = uldb_getIterator(&iter)) {
                LOG_ADD0("Couldn't get database iterator");
                log_log(LOG_ERR);
                status = 3;
            }
            else {
                const uldb_Entry* entry;

                status = 0;

                for (entry = uldb_iter_firstEntry(iter); NULL != entry; entry =
                        uldb_iter_nextEntry(iter)) {
                    prod_class* prodClass;

                    if (uldb_entry_getProdClass(entry, &prodClass)) {
                        LOG_ADD0(
                                "Couldn't get product-class of database entry");
                        log_log(LOG_ERR);
                        status = 3;
                        break;
                    }
                    else {
                        const struct sockaddr_in* sockAddr =
                                uldb_entry_getSockAddr(entry);
                        char buf[2048];
                        const char* const type = 
                                uldb_entry_isNotifier(entry)
                                    ? "notifier" : "feeder";

                        (void) s_prod_class(buf, sizeof(buf), prodClass);
                        (void) printf("%ld %d %s %s %s\n",
                                (long) uldb_entry_getPid(entry),
                                uldb_entry_getProtocolVersion(entry),
                                type, hostbyaddr(sockAddr), buf);
                        free_prod_class(prodClass);
                    } /* "prodClass" allocated */
                } /* entry loop */

                uldb_iter_free(iter);
            } /* got database iterator */
        } /* database opened */
    } /* correct invocation syntax */

    exit(status);
}
