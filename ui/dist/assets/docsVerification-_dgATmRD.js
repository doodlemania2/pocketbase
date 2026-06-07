function c(e){const a=app.utils.getApiExampleURL(),o=[{title:"Request verification",content:l},{title:"Confirm verification",content:r}],n=store({activeActionIndex:0});return t.div({pbEvent:"apiPreviewVerification",className:"content"},t.p(null,`Sends ${e.name} account verification request.`),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
                        import PocketBase from 'pocketbase';

                        const pb = new PocketBase('${a}');

                        ...

                        await pb.collection('${e.name}').requestVerification('test@example.com');

                        // ---
                        // (optional) in your custom confirmation page:
                        // ---

                        await pb.collection('${e.name}').confirmVerification('VERIFICATION_TOKEN');
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
                        import 'package:pocketbase/pocketbase.dart';

                        final pb = PocketBase('${a}');

                        ...

                        await pb.collection('${e.name}').requestVerification('test@example.com');

                        // ---
                        // (optional) in your custom confirmation page:
                        // ---

                        await pb.collection('${e.name}').confirmVerification('VERIFICATION_TOKEN');
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        # Request verification
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "email":"..." }' \\
                          '${a}/api/collections/${e.name}/request-verification'

                        # Confirm verification
                        curl -X POST \\
                          -H 'Content-Type:application/json' \\
                          -d '{ "token":"..." }' \\
                          '${a}/api/collections/${e.name}/confirm-verification'
                    `}]}),t.nav({className:"btns m-t-base m-b-sm"},()=>o.map((s,i)=>t.button({type:"button",className:()=>`btn sm expanded ${n.activeActionIndex==i?"active":"secondary"}`,textContent:()=>s.title,onclick:()=>n.activeActionIndex=i}))),()=>{var s,i;return(i=(s=o[n.activeActionIndex])==null?void 0:s.content)==null?void 0:i.call(s,e)})}function l(e){const a=[{title:204,value:"null"},{title:400,value:`
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
            `}];return[t.div({className:"block"},t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/request-verification`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"email ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The auth record email address to send the verification request (if exists).")))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:a})]}function r(e){const a=[{title:204,value:"null"},{title:400,value:`
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
            `}];return[t.div({className:"block"},t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/confirm-verification`)),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"token ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"The token from the verification request email.")))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:a})]}export{c as docsVerification};
