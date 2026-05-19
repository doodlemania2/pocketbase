function d(e){const a=app.utils.getApiExampleURL(),r=[{title:"Request password reset",content:i},{title:"Confirm password reset",content:o}],n=store({activeActionIndex:0});return t.div({pbEvent:"apiPreviewPasswordReset",className:"content"},t.p(null,`Sends ${e.name} password reset email request.`),t.p(null,"On successful password reset all previously issued auth tokens for the specific record will be invalidated (and the user will be marked as verified if not already)."),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
                        import PocketBase from 'pocketbase';

                        const pb = new PocketBase('${a}');

                        ...

                        await pb.collection('${e.name}').requestPasswordReset('test@example.com');

                        // ---
                        // (optional) in your custom confirmation page:
                        // ---

                        // note: all previous user auth tokens will be invalidated
                        // (and the user will be marked as verified if not already)
                        await pb.collection('${e.name}').confirmPasswordReset(
                            'RESET_TOKEN',
                            'NEW_PASSWORD',
                            'NEW_PASSWORD_CONFIRM',
                        );
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
                        import 'package:pocketbase/pocketbase.dart';

                        final pb = PocketBase('${a}');

                        ...

                        await pb.collection('${e.name}').requestPasswordReset('test@example.com');

                        // ---
                        // (optional) in your custom confirmation page:
                        // ---

                        // note: all previous user auth tokens will be invalidated
                        // (and the user will be marked as verified if not already)
                        await pb.collection('${e.name}').confirmPasswordReset(
                          'RESET_TOKEN',
                          'NEW_PASSWORD',
                          'NEW_PASSWORD_CONFIRM',
                        );
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        # Request password reset
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "email":"..." }' \\
                          '${a}/api/collections/${e.name}/request-password-reset'

                        # Confirm password reset
                        #
                        # note: all previous user auth tokens will be invalidated
                        # (and the user will be marked as verified if not already)
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "token":"...", "password":"", "passwordConfirm":"" }' \\
                          '${a}/api/collections/${e.name}/confirm-password-reset'
                    `}]}),t.nav({className:"btns m-t-base m-b-sm"},()=>r.map((s,l)=>t.button({type:"button",className:()=>`btn sm expanded ${n.activeActionIndex==l?"active":"secondary"}`,textContent:()=>s.title,onclick:()=>n.activeActionIndex=l}))),()=>{var s,l;return(l=(s=r[n.activeActionIndex])==null?void 0:s.content)==null?void 0:l.call(s,e)})}function i(e){const a=[{title:204,value:"null"},{title:400,value:`
                {
                  "status": 400,
                  "message": "An error occurred while validating the submitted data.",
                  "data": {
                    "email": {
                      "code": "validation_required",
                      "message": "Missing required value."
                    }
                  }
                }
            `}];return[t.div({className:"block"},t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/request-password-reset`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"email ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The auth record email address to send the password reset request (if exists).")))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:a})]}function o(e){const a=[{title:204,value:"null"},{title:400,value:`
                {
                  "status": 400,
                  "message": "An error occurred while validating the submitted data.",
                  "data": {
                    "token": {
                      "code": "validation_required",
                      "message": "Missing required value."
                    }
                  }
                }
            `}];return[t.div({className:"block"},t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/confirm-password-reset`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"token ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The token from the password reset request email.")),t.tr(null,t.td({className:"min-width"},"password ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The new password to set.")),t.tr(null,t.td({className:"min-width"},"passwordConfirm ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"Confirmation of the new password.")))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:a})]}export{d as docsPasswordReset};
