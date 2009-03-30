/*
 *  SetupHelper.h
 *  AwkwardTV
 *
 *  Created by Alan Quatermain on 11/04/07.
 *  Copyright 2007 AwkwardTV. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>

struct _ATVSetupHelperCommand
{
    unsigned int cmdCode;
    union
    {
        char sourcePath[PATH_MAX];
        BOOL enable;

    } params;
};
typedef struct _ATVSetupHelperCommand ATVSetupHelperCommand;

enum
{
    kATVUpdateSelf          = 'upds',
    kATVInstallAppliance    = 'insa',
    kATVInstallScreenSaver  = 'inss',
    kATVInstallQTCodec      = 'insc',
    kATVSecureShellInstall  = 'sshi',
    kATVSecureShellChange   = 'sshc',
    kATVAppleShareChange    = 'afpc',
    kATVDeleteReplacedFiles = 'delr'

};
