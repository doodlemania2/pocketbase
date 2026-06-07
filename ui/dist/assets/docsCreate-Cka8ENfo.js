import{e as f}from"./expandInfo-CTyADVsr.js";import{f as y}from"./fieldsInfo-CSZqlaEr.js";function k(e){var p,c;const i=app.utils.getApiExampleURL(),s=e.createRule===null,r=e.type==="auth",o=r?["password","verified","email","emailVisibility"]:[],n=((p=e.fields)==null?void 0:p.filter(a=>!a.hidden&&a.type!="autodate"&&!o.includes(a.name)))||[],m={collectionId:e.id,collectionName:e.name},u=[{title:200,value:JSON.stringify(Object.assign(m,app.utils.getDummyFieldsData(e)),null,2)},{title:400,value:`
                {
                  "status": 400,
                  "message": "Failed to create record.",
                  "data": {
                    "${r?"email":((c=n.find(a=>!a.primaryKey))==null?void 0:c.name)||"someField"}": {
                      "code": "validation_required",
                      "message": "Missing required value."
                    }
                  }
                }
            `}];return s&&u.push({title:403,value:`
                {
                  "status": 403,
                  "message": "Only superusers can perform this action.",
                  "data": {}
                }
            `}),t.div({pbEvent:"apiPreviewCreate",className:"content"},t.p(null,`Creates a new ${e.name} record.`),t.p(null,"Body parameters could be sent as ",t.code(null,"application/json")," or ",t.code(null,"multipart/form-data"),"."),t.p(null,"File upload is supported only via ",t.code(null,"multipart/form-data"),". For more info and examples you could check the detailed ",t.a({href:"https://pocketbase.io/docs/files-handling",target:"_blank",rel:"noopener noreferrer",textContent:"Files upload and handling docs"}),"."),app.components.codeBlockTabs({className:"sdk-examples m-t-sm",historyKey:"pbLastSDK",tabs:[{title:"JS SDK",language:"js",value:`
import PocketBase from 'pocketbase';

const pb = new PocketBase('${i}');

...

// example create body
const body = ${N(JSON.stringify(b(e),null,2))};

const record = await pb.collection('${e.name}').create(body);
`+(r?`
// (optional) send an email verification request
await pb.collection('${e==null?void 0:e.name}').requestVerification('test@example.com');
`:""),footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/js-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"JS SDK docs"}))},{title:"Dart SDK",language:"dart",value:`
import 'package:pocketbase/pocketbase.dart';

final pb = PocketBase('${i}');

...

// example create body
final body = <String, dynamic>${JSON.stringify(w(e),null,2)};

final record = await pb.collection('${e.name}').create(body: body, files: []);
`+(r?`
// (optional) send an email verification request
await pb.collection('${e==null?void 0:e.name}').requestVerification('test@example.com');
`:""),footnote:t.div({className:"txt-right"},t.a({href:"https://github.com/pocketbase/dart-sdk",target:"_blank",rel:"noopener noreferrer",textContent:"Dart SDK docs"}))},{title:"curl",language:"bash",value:`
                        curl -X POST \\
                          -H 'Authorization:TOKEN' \\
                          -H 'Content-Type:application/json' \\
                          -d '{ ... }' \\
                          '${i}/api/collections/${e.name}/records/RECORD_ID'
                    `}]}),t.div({className:"block m-t-base"},t.strong(null,"API details")),t.div({className:"alert success api-preview-alert"},t.span({className:"label method"},"POST"),t.span({className:"path"},`/api/collections/${e.name}/records`),()=>{if(s)return t.small({className:"extra"},"Requires superuser Authorization:TOKEN header")}),t.table({className:"api-preview-table body-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"Body params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,()=>{if(r)return[t.tr(null,t.th({colSpan:99},"Auth specific fields")),t.tr(null,t.td({className:"min-width"},"email ",()=>{var a,l;return(l=(a=e.fields)==null?void 0:a.find(d=>d.name=="email"))!=null&&l.required?t.em(null,"(required)"):t.em(null,"(optional)")}),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"Auth record email address.")),t.tr(null,t.td({className:"min-width"},"emailVisibility ",()=>{var a,l;return(l=(a=e.fields)==null?void 0:a.find(d=>d.name=="emailVisibility"))!=null&&l.required?t.em(null,"(required)"):t.em(null,"(optional)")}),t.td({className:"min-width"},t.span({className:"label"},"Boolean")),t.td(null,"Whether to show/hide the auth record email when fetching the record data.",t.br(),"Superusers and the owner of the record always have access to the email address.")),t.tr(null,t.td({className:"min-width"},"password ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"Auth record password.")),t.tr(null,t.td({className:"min-width"},"passwordConfirm ",t.em(null,"(required)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,"Auth record password confirmation.")),t.tr(null,t.td({className:"min-width"},"verified ",t.em(null,"(optional)")),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,t.p(null,"Indicates whether the auth record is verified or not."),t.p(null,'This field can be set only by superusers or auth records with "Manage" access.'))),t.tr(null,t.th({colSpan:99},"Other fields"))]},()=>n.map(a=>t.tr(null,t.td({className:"min-width"},a.name,t.em(null,a.required&&!a.autogeneratePattern?" (required)":" (optional)")),t.td({className:"min-width"},t.span({className:"label"},()=>{var h;const l=(h=app.fieldTypes[a.type])==null?void 0:h.dummyData(a,!0),d=typeof l;return a.type=="file"?"File":d==="string"?"String":d=="number"?"Number":d=="bool"?"Boolean":Array.isArray(l)?"Array":app.utils.isObject(l)?"Object":"Mixed"})),t.td(null,t.code(null,a.type)," field type value.",t.br(),t.small({className:"txt-hint"},"For more details you could check the ",t.a({href:"https://pocketbase.io/docs/collections/#fields",target:"_blank",rel:"noopener noreferrer",textContent:"Fields docs"}),".")))))),t.table({className:"api-preview-table query-params"},t.thead(null,t.tr(null,t.th({className:"min-width txt-primary"},"?query params"),t.th({className:"min-width"},"Type"),t.th(null,"Description"))),t.tbody(null,t.tr(null,t.td({className:"min-width"},"expand"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,f())),t.tr(null,t.td({className:"min-width"},"fields"),t.td({className:"min-width"},t.span({className:"label"},"String")),t.td(null,y())))),t.div({className:"block m-t-base m-b-sm"},t.strong(null,"Example responses")),app.components.codeBlockTabs({tabs:u}))}function N(e){return e.replaceAll('"[[',"").replaceAll(']]"',"")}function b(e,i=!1){let s=app.utils.getDummyFieldsData(e,!0);return delete s.id,e.type=="auth"&&(i&&(s.oldPassword="987654321",delete s.email),s.password="123456789",s.passwordConfirm="123456789",delete s.verified),s}function w(e,i=!1){var r,o;const s=b(e,i);for(const n in s){const m=typeof s[n];((o=(r=s[n])==null?void 0:r.startsWith)!=null&&o.call(r,"[[")||!["number","string","boolean"].includes(m)&&!Array.isArray(s[n]))&&delete s[n]}return s}export{k as docsCreate,b as fullDummyPayload,w as primitivesDummyPayload,N as replaceDummyPayloadPlaceholder};
