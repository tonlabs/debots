pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

import "../Debot.sol";
import "../Terminal.sol";
import "../Menu.sol";
import "../AddressInput.sol";
import "../ConfirmInput.sol";
import "../Upgradable.sol";

struct Task {
    uint32 id;
    string text;
    uint64 createdAt;
    bool isDone;
}

struct Stat {
    uint32 completeCount;
    uint32 incompleteCount;
}

interface IMsig {
   function sendTransaction(address dest, uint128 value, bool bounce, uint8 flags, TvmCell payload  ) external;
}     


abstract contract ATodo {
   constructor(uint256 pubkey) public {}
}

interface ITodo {

   function createTask(string text) external;
   function updateTask(uint32 id, bool done) external;
   function deleteTask(uint32 id) external;
   function getTasks() external returns (Task[] tasks);
   function getStat() external returns (Stat);
}




contract TodoDebot is Debot {
    TvmCell m_todoCode; // TODO contract code
    address m_address;  // TODO contract address
    Stat m_stat;        // Statistics of incompleted and completed tasks
    uint32 m_taskId;    // Task id for update. I didn't find a way to make this var local
    uint256 m_masterPubKey;


    function setTodoCode(TvmCell code) public {
        require(msg.pubkey() == tvm.pubkey(), 101);
        tvm.accept();
        m_todoCode = code;
    }


    function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Operation failed. sdkError {}, exitCode {}", sdkError, exitCode));
        _menu();
    }

    function onSuccess() public {
        Terminal.print(0, "Transaction succeeded.");
        _getStat(tvm.functionId(setStat));
    }

    function start() public override {
        enterPublicKey();
    }


    function enterPublicKey() public {
        Terminal.input(tvm.functionId(savePublicKey),"Please enter your public key",false);
    }


    function savePublicKey(string value) public {
        uint res;
        bool status;
        (res, status) = stoi("0x"+value);
        if (status) {
            m_masterPubKey = res;
            ConfirmInput.get(tvm.functionId(inputAddressOrDeployNew),"Do you already have TODO list?");
        } else {
            Terminal.input(tvm.functionId(savePublicKey),"Wrong public key. Try again!\nPlease enter your public key",false);
        }
    }

    function inputAddressOrDeployNew(bool value) public {
        if ( value ) {
            AddressInput.get(tvm.functionId(enterTodoAddr),"Enter your TODO contract address");
        } else {
            deployNewTodoContract();
        }
    }

    function deployNewTodoContract() public {
        TvmCell deployState = tvm.insertPubkey(m_todoCode, m_masterPubKey);
        m_address = address.makeAddrStd(0, tvm.hash(deployState));

        Terminal.print(0, "New TODO contract with an initial balance of 0.1 will be deployed, please save its address:");
        Terminal.print(0, format("{}",m_address));

        AddressInput.get(tvm.functionId(creditAccount),"Select a wallet for payment");
    }


    function creditAccount(address value) public view {
        optional(uint256) pubkey = 0;
        TvmCell empty;
        IMsig(value).sendTransaction{
            abiVer: 2,
            extMsg: true,
            sign: true,
            pubkey: pubkey, 
            time: uint64(now), 
            expire: 0,
            callbackId: tvm.functionId(deploy),
            onErrorId: tvm.functionId(creditAccount)
        }(m_address, 200000000, false, 3, empty);

    }

    function deploy() public  {
        Terminal.print(0, "wwww");
            TvmCell image = tvm.insertPubkey(m_todoCode, m_masterPubKey);
            optional(uint256) none;
        Terminal.print(0, "2www");
            TvmCell deployMsg = tvm.buildExtMsg({
                abiVer: 2,
                dest: m_address,
                callbackId: tvm.functionId(onSuccess),
                onErrorId:  tvm.functionId(deploy),  // cycle
                time: 0,
                expire: 0,
                sign: true,
                pubkey: none,
                stateInit: image,
                call: {ATodo, m_masterPubKey}
            });
            tvm.sendrawmsg(deployMsg, 1);
    }

    function setStat(Stat stat) public {
        m_stat = stat;
        _menu();
    }

    function enterTodoAddr(address value) public {
        m_address = value;
        _getStat(tvm.functionId(setStat));
    }

    function _menu() private {
        string sep = '----------------------------------------';
        Terminal.print(0, sep);
        Menu.select(
            format(
                "You have {}/{}/{} (todo/done/total) tasks",
                    m_stat.incompleteCount,
                    m_stat.completeCount,
                    m_stat.completeCount + m_stat.incompleteCount
            ),
            sep,
            [
                MenuItem("Create new task","",tvm.functionId(createTask)),
                MenuItem("Show task list","",tvm.functionId(showTasks)),
                MenuItem("Update task status","",tvm.functionId(updateTask)),
                MenuItem("Delete task","",tvm.functionId(deleteTask))
            ]
        );
        Terminal.print(0, "");
    }

    function createTask(uint32 index) public {
        index = index;
        Terminal.input(tvm.functionId(createTask_), "One line please:", false);
    }

    function createTask_(string value) public view {
        optional(uint256) pubkey = 0;
        ITodo(m_address).createTask{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(value);
    }

    function showTasks(uint32 index) public view {
        index = index;
        optional(uint256) none;
        ITodo(m_address).getTasks{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: none,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(showTasks_),
            onErrorId: 0
        }();
    }

    function showTasks_( Task[] tasks ) public {
        uint32 i;
        if (tasks.length > 0 ) {
            Terminal.print(0, "Your tasks list:");
            for (i = 0; i < tasks.length; i++) {
                Task task = tasks[i];
                string completed;
                if (task.isDone) {
                    completed = '✓';
                } else {
                    completed = ' ';
                }
                Terminal.print(0, format("{} {}  \"{}\"  at {}", task.id, completed, task.text, task.createdAt));
            }
        } else {
            Terminal.print(0, "Your tasks list is empty");
        }
        _menu();
    }

    function updateTask(uint32 index) public {
        index = index;
        if (m_stat.completeCount + m_stat.incompleteCount > 0) {
            Terminal.input(tvm.functionId(updateTask_), "Enter task number:", false);
        } else {
            Terminal.print(0, "Sorry, you have no tasks to update");
            _menu();
        }
    }

    function updateTask_(string value) public {
        (uint256 num,) = stoi(value);
        m_taskId = uint32(num);
        ConfirmInput.get(tvm.functionId(updateTask__),"Is this task completed?");
    }

    function updateTask__(bool value) public view {
        optional(uint256) pubkey = 0;
        ITodo(m_address).updateTask{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(m_taskId, value);
    }


    function deleteTask(uint32 index) public {
        index = index;
        if (m_stat.completeCount + m_stat.incompleteCount > 0) {
            Terminal.input(tvm.functionId(deleteTask_), "Enter task number:", false);
        } else {
            Terminal.print(0, "Sorry, you have no tasks to delete");
            _menu();
        }
    }

    function deleteTask_(string value) public view {
        (uint256 num,) = stoi(value);
        optional(uint256) pubkey = 0;
        ITodo(m_address).deleteTask{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(onSuccess),
                onErrorId: tvm.functionId(onError)
            }(uint32(num));
    }

    function _getStat(uint32 answerId) private view {
        optional(uint256) none;
        ITodo(m_address).getStat{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: none,
            time: uint64(now),
            expire: 0,
            callbackId: answerId,
            onErrorId: 0
        }();
    }

    // @notice Define DeBot version and title here.
    function getVersion() public override returns (string name, uint24 semver) {
        (name, semver) = ("TODO DeBot", _version(0,1,0));
    }

    function _version(uint24 major, uint24 minor, uint24 fix) private pure inline returns (uint24) {
        return (major << 16) | (minor << 8) | (fix);
    }
}
