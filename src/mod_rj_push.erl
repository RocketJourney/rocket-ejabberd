-module (mod_rj_push).

-author ('zgbjgg@gmail.com').

-behavior(gen_mod).

%% API:
-export([start/2, stop/1, reload/3, depends/2]).

-export([user_send_packet/1, mod_opt_type/1]).

-include("ejabberd.hrl").
-include("logger.hrl").
-include("xmpp.hrl").

start(Host, _Opts) ->
    %% why priority 91: we must run AFTER all other hooks (last logdb)
    ejabberd_hooks:add(user_send_packet,Host, ?MODULE, user_send_packet, 91),
    ok.

stop(Host) ->
    %% why priority 91: we must run AFTER all other hooks (last logdb)
    ejabberd_hooks:delete(user_send_packet,Host, ?MODULE, user_send_packet, 91),
    ok.

reload(_Host, _NewOpts, _OldOpts) ->
    ok.

depends(_Host, _Opts) ->
    [].

-spec user_send_packet({stanza(), ejabberd_c2s:state()})
      -> {stanza(), ejabberd_c2s:state()} | {stop, {stanza(), ejabberd_c2s:state()}}.
user_send_packet({#message{body = Body, type = Type} = Packet, C2SState}) ->
    From = xmpp:get_from(Packet),
    To = xmpp:get_to(Packet),
    ok = case Type of
        chat      ->
            ok; % ignore for now, RJ only uses groupchat
        groupchat ->
            % get subscribers of muc room
            Subscribers = begin
                SubscribersRoom = mod_muc_admin:get_subscribers(To#jid.luser, To#jid.lserver),
                lists:map(fun(SJID) ->
                    JID = jid:from_string(SJID),
                    JID#jid.luser
                end, SubscribersRoom)
            end,
            Text = xmpp:get_text(Body),
            push_call(From#jid.lserver, From#jid.luser, To#jid.luser, Text, Subscribers);     
        _               ->
            ok % ignore other type of message
    end,
    {Packet, C2SState};
user_send_packet(Acc) ->
    Acc.

push_call(LServer, From, To, Text, Subscribers) ->
    Mod = gen_mod:get_module_opt(LServer, ?MODULE, push_mod, unknown),
    Fun = gen_mod:get_module_opt(LServer, ?MODULE, push_fun, unknown),
    push_call(Mod, Fun, From, To, Text, Subscribers).

push_call(unknown, unknown, _From, _To, _Text, _Subscribers) ->
    ?DEBUG("Not set either push mod or push fun in opts", []);
push_call(unknown, _Fun, _From, _To, _Text, _Subscribers)    ->
    ?DEBUG("Not set push mod in opts", []);
push_call(_Mod, unknown, _From, _To, _Text, _Subscribers)    ->
    ?DEBUG("Not set push fun in opts", []);
push_call(Mod, Fun, From, To, Text, Subscribers)             ->
    Res = Mod:Fun(From, To, Text, Subscribers),
    ?DEBUG("Sending push call was ~p", [Res]),
    ok.

mod_opt_type(push_mod) ->
    fun(B) when is_list(B)   -> list_to_atom(B);
       (B) when is_binary(B) -> list_to_atom(binary_to_list(B));
       (B) -> B end;
mod_opt_type(push_fun) ->
    fun(B) when is_list(B)   -> list_to_atom(B);
       (B) when is_binary(B) -> list_to_atom(binary_to_list(B));
       (B) -> B end;
mod_opt_type(_) ->
    [push_mod, push_fun].
