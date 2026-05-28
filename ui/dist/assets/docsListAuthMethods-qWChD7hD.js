import{f as n}from"./fieldsInfo-CSZqlaEr.js";function r(a){const l=app.utils.getApiExampleURL(),e=store({isLoading:!1,authMethods:[],get responses(){return[{title:200,value:e.isLoading?"...":JSON.stringify(e.authMethods,null,2)},{title:404,value:`
                        {
                          "status": 404,
                          "message": "Missing collection context.",
                          "data": {}
                        }
                    `}]}});async function o(){e.isLoading=!0;try{e.authMethods=await app.pb.collection(a.name).listAuthMethods(),e.isLoading=!1}catch(s){s!=null&&s.isAbort||(app.checkApiError(s),e.isLoading=!1)}}return t.div({pbEvent:"apiPreviewListAuthMethods",className:"content",onmount:()=>{o()}},t.p(null,`Returns a public list with all allowed ${a.name} authentication methods.`),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
                        import PocketBase from 'pocketbase';

                        const pb = new PocketBase('${l}');

                        ...

                        const result = await pb.collection('${a.name}').listAuthMethods();
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
                        import 'package:pocketbase/pocketbase.dart';

                        final pb = PocketBase('${l}');

                        ...

                        final result = await pb.collection('${a.name}').listAuthMethods();
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        curl '${l}/api/collections/${a.name}/auth-methods'
                    `}]}),t.div({className:"block m-t-base"},t.strong(null,"API details")),t.div({className:"alert info api-preview-alert"},t.span({className:"label method"},"GET"),t.span({className:"path"},`/api/collections/${a.name}/auth-methods`)),t.table({className:"api-preview-table query-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"?query params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"fields"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,n())))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:()=>e.responses}))}export{r as docsListAuthMethods};
