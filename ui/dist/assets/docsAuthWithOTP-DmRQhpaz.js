import{e as o}from"./expandInfo-CTyADVsr.js";import{f as r}from"./fieldsInfo-CSZqlaEr.js";function c(e){const a=app.utils.getApiExampleURL(),n=[{title:"OTP request",content:d},{title:"OTP auth",content:m}],i=store({activeActionIndex:0});return t.div({pbEvent:"apiPreviewAuthWithOTP",className:"content"},t.p(null,"Authenticate with an one-time/short-lived password (OTP)."),t.p(null,"On successful authentication the user will be also marked as verified (if the OTP source is email and the user is not verified already)."),t.p(null,"Note that when requesting an OTP we return an ",t.code(null,"otpId")," even if a user with the provided email doesn't exist as a very basic enumeration protection."),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
                        import PocketBase from 'pocketbase';

                        const pb = new PocketBase('${a}');

                        ...

                        // send OTP email to the provided auth record
                        const req = await pb.collection('${e.name}').requestOTP('test@example.com');

                        // ... show a screen/popup to enter the password from the email ...

                        // authenticate with the requested OTP id and the email password
                        const authData = await pb.collection('${e.name}').authWithOTP(
                            req.otpId,
                            "YOUR_OTP",
                        );

                        // after the above you can also access the auth data from the authStore
                        console.log(pb.authStore.isValid);
                        console.log(pb.authStore.token);
                        console.log(pb.authStore.record.id);

                        // "logout"
                        pb.authStore.clear();
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
                        import 'package:pocketbase/pocketbase.dart';

                        final pb = PocketBase('${a}');

                        ...

                        // send OTP email to the provided auth record
                        final req = await pb.collection('${e.name}').requestOTP('test@example.com');

                        // ... show a screen/popup to enter the password from the email ...

                        // authenticate with the requested OTP id and the email password
                        final authData = await pb.collection('${e.name}').authWithOTP(
                            req.otpId,
                            "YOUR_OTP",
                        );

                        // after the above you can also access the auth data from the authStore
                        print(pb.authStore.isValid);
                        print(pb.authStore.token);
                        print(pb.authStore.record.id);

                        // "logout"
                        pb.authStore.clear();
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        # OTP request (sends email to the user if exists)
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "email":"..." }' \\
                          '${a}/api/collections/${e.name}/request-otp'

                        # OTP auth
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "otpId":"...", "password":"..." }' \\
                          '${a}/api/collections/${e.name}/auth-with-otp'
                    `}]}),t.nav({className:"btns m-t-base m-b-sm"},()=>n.map((s,l)=>t.button({type:"button",className:()=>`btn sm expanded ${i.activeActionIndex==l?"active":"secondary"}`,textContent:()=>s.title,onclick:()=>i.activeActionIndex=l}))),()=>{var s,l;return(l=(s=n[i.activeActionIndex])==null?void 0:s.content)==null?void 0:l.call(s,e)})}function d(e){const a=[{title:200,value:`
                {
                  "otpId": "njvv1b1lkdbpp3m"
                }
            `},{title:400,value:`
                {
                  "status": 400,
                  "message": "An error occurred while validating the submitted data.",
                  "data": {
                    "email": {
                      "code": "validation_is_email",
                      "message": "Must be a valid email address."
                    }
                  }
                }
            `},{title:429,value:`
                {
                  "status": 429,
                  "message": "You've send too many OTP requests, please try again later.",
                  "data": {}
                }
            `}];return[t.div(null,t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/request-otp`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"email ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The auth record email address to send the OTP request (if exists).")))),t.div({className:"m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:a})]}function m(e){const a={collectionId:e.id,collectionName:e.name},n=[{title:200,value:JSON.stringify({token:"...JWT...",record:Object.assign(a,app.utils.getDummyFieldsData(e))},null,2)},{title:400,value:`
                {
                  "status": 400,
                  "message": "Failed to authenticate.",
                  "data": {
                    "otpId": {
                      "code": "validation_required",
                      "message": "Missing required value."
                    }
                  }
                }
            `}];return[t.div(null,t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/auth-with-otp`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"otpId ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The id of the OTP request.")),t.tr(null,t.td({className:"min-width"},"password ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The one-time/short-lived password from the OTP request.")))),t.table({className:"api-preview-table query-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"?query params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"expand"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,o())),t.tr(null,t.td({className:"min-width"},"fields"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,r())))),t.div({className:"m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:n})]}export{c as docsAuthWithOTP};
