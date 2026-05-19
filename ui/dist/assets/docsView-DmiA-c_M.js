import{e as r}from"./expandInfo-CTyADVsr.js";import{f as i}from"./fieldsInfo-CSZqlaEr.js";function p(e){const a=app.utils.getApiExampleURL(),l=e.viewRule===null,n={collectionId:e.id,collectionName:e.name},s=[{title:200,value:JSON.stringify(Object.assign(n,app.utils.getDummyFieldsData(e)),null,2)}];return l&&s.push({title:403,value:`
                {
                  "status": 403,
                  "message": "Only superusers can access this action.",
                  "data": {}
                }
            `}),s.push({title:404,value:`
            {
              "status": 404,
              "message": "The requested resource wasn't found.",
              "data": {}
            }
        `}),t.div({pbEvent:"apiPreviewView",className:"content"},t.p(null,`Fetch a single ${e.name} record.`),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
                        import PocketBase from 'pocketbase';

                        const pb = new PocketBase('${a}');

                        ...

                        const record = await pb.collection('${e.name}').getOne('RECORD_ID', {
                            expand: 'relField1,relField2.subRelField',
                        });
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
                        import 'package:pocketbase/pocketbase.dart';

                        final pb = PocketBase('${a}');

                        ...

                        final record = await pb.collection('${e.name}').getOne('RECORD_ID',
                          expand: 'relField1,relField2.subRelField',
                        );
                    `,footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        curl \\
                          -H 'Authorization:TOKEN' \\
                          '${a}/api/collections/${e.name}/records/RECORD_ID'
                    `}]}),t.div({className:"block m-t-base"},t.strong(null,"API details")),t.div({className:"alert info api-preview-alert"},t.span({className:"label method"},"GET"),t.span({className:"path"},`/api/collections/${e.name}/records/`,t.strong(null,":id")),()=>{if(l)return t.small({className:"extra"},"Requires superuser Authorization:TOKEN header")}),t.table({className:"api-preview-table path-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Path params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"id"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"ID of the record to view.")))),t.table({className:"api-preview-table query-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"?query params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"expand"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,r())),t.tr(null,t.td({className:"min-width"},"fields"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,i())))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:s}))}export{p as docsView};
