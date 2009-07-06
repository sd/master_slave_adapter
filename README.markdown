master_slave_adapter
====================


Quick setup
-----------

Just use 'master_slave_adapter' in your database.yml:

    production:
      adapter: master_slave_adapter
      real_adapter: mysql
      master:
        database: app_production
        username: rails
        password: ********
        host: masterdb.example.com
      slave:
        database: app_production
        username: rails
        password: ********
        host: slavedb.example.com

- No matter what, all "write" calls go to the master. 
- Inside transactions, all calls go to the master. 
- Inside Observers, all calls go to the master.

By default, all other "read" calls will go to the slave, unless you add "default: master" to
the options in database.yml.

If you want to control when the slave is used, you can specify which server you want to use 
(for the 'read' calls) by using:

TheModel.with_master do
  ...
end

TheModel.with_slave do
  ...
end


Credits
=======
A lot of inspiration and understanding of the problem came from Rick Olsen's Masochism.
  
-------------------------------------------------------------------------------
Copyright (c) 2009 Sebastian Delmont <sd@notso.net> 
Copyright (c) 2009, 2008 StreetEasy / NMD Interactive <http://www.streeteasy.com/> 
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this 
list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this
list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.

* Neither the name of Sebastian Delmont, nor StreetEasy nor NMD Interactive 
nor the names of their contributors may be used to endorse or promote products 
derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-------------------------------------------------------------------------------